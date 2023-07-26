const xcode = require('xcode');
const path = require('path');
const fs = require('fs').promises;

// Function to search a file in a directory and its subdirectories
async function searchFileInDirectory(startPath, filter){
    let results = [];
    const files = await fs.readdir(startPath);
    for(let i=0; i<files.length; i++){
        const filename = path.join(startPath, files[i]);
        const stat = await fs.lstat(filename);
        if(stat.isDirectory()){
            results = results.concat(await searchFileInDirectory(filename, filter)); // recurse
        }
        else if(filter.test(filename)) results.push(filename);
    }
    return results;
}

// Get root path
const rootPath = process.argv[2];

// Define the patterns to search for
const projPattern = /\.pbxproj$/;
const appDelegatePattern = /AppDelegate\.swift$/;

async function checkProject() {
    // Search for the .pbxproj and AppDelegate.swift files
    const [projectPaths, appDelegatePaths] = await Promise.all([
        searchFileInDirectory(rootPath, projPattern),
        searchFileInDirectory(rootPath, appDelegatePattern)
    ]);

    for (let projectPath of projectPaths) {
        const project = xcode.project(projectPath);
        project.parseSync();

        console.log(`Checking project at path: ${projectPath}`);

        const targets = project.pbxNativeTargetSection();
        let hasNotificationServiceExtension = false;

        for (let key in targets) {
            const target = targets[key];
            if (target && target.productType === "com.apple.product-type.app-extension") {
                const name = target.name.replace(/"/g, "");
                if (name.endsWith("NotificationServiceExtension")) {
                    hasNotificationServiceExtension = true;
                    break;
                }
            }
        }

        if (hasNotificationServiceExtension) {
            console.log("Notification Service Extension found");
        } else {
            console.log("Notification Service Extension not found");
        }
    }

    for (let appDelegatePath of appDelegatePaths) {
        console.log(`Checking AppDelegate at path: ${appDelegatePath}`);
        try {
            const contents = await fs.readFile(appDelegatePath, 'utf8');
            if (contents.includes("func userNotificationCenter(")) {
                console.log("Required method found in AppDelegate.swift");
            } else {
                console.log("Required method not found in AppDelegate.swift");
            }
        } catch(err) {
            console.error("Error reading file:", err);
        }
    }
}

checkProject().catch(console.error);
