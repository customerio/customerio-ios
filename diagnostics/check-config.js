const xcode = require('xcode');
const path = require('path');
const fs = require('fs').promises;

// This function searches for files within a directory and its subdirectories, filtering them by a given regular expression.
async function searchFileInDirectory(startPath, filter){
    let results = [];
    const files = await fs.readdir(startPath);
    const tasks = files.map(async (file) => {
        // Construct the full path of the file
        const filename = path.join(startPath, file);
        // Get file stats
        const stat = await fs.lstat(filename);
        // If it's a directory, recurse into this directory
        if(stat.isDirectory()){
            const subDirResults = await searchFileInDirectory(filename, filter);
            // Combine results
            results = results.concat(subDirResults);
        }
        // If the filename matches the filter, add it to the results
        else if(filter.test(filename)) results.push(filename);
    });

    // Wait for all tasks to complete
    await Promise.all(tasks);

    return results;
}

// Get root path from the command line arguments
const rootPath = process.argv[2];

// Define the patterns to search for
const projPattern = /\.pbxproj$/; // pattern for Xcode project files
const appDelegatePattern = /AppDelegate\.swift$/; // pattern for AppDelegate.swift files

async function checkProject() {
    // Search for the .pbxproj and AppDelegate.swift files
    const [projectPaths, appDelegatePaths] = await Promise.all([
        searchFileInDirectory(rootPath, projPattern),
        searchFileInDirectory(rootPath, appDelegatePattern)
    ]);

    // For each project file found...
    for (let projectPath of projectPaths) {
        // Parse the project file
        const project = xcode.project(projectPath);
        project.parseSync();

        console.log(`Checking project at path: ${projectPath}`);

        // Get all targets in the project
        const targets = project.pbxNativeTargetSection();
        let hasNotificationServiceExtension = false;

        // Check if there is a Notification Service Extension target
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

        // Log whether or not a Notification Service Extension was found
        if (hasNotificationServiceExtension) {
            console.log("Notification Service Extension found");
        } else {
            console.log("Notification Service Extension not found");
        }
    }

    // For each AppDelegate.swift file found...
    for (let appDelegatePath of appDelegatePaths) {
        console.log(`Checking AppDelegate at path: ${appDelegatePath}`);
        try {
            // Read the file's content
            const contents = await fs.readFile(appDelegatePath, 'utf8');
            // Check if it contains the required method
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

// Call the checkProject function and catch any errors
checkProject().catch(console.error);
