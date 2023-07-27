const xcode = require('xcode');
const path = require('path');
const fs = require('fs').promises;

/**
 * Search for a specific file within a directory and all its subdirectories.
 * @param {string} startPath - Path of the directory to start the search from.
 * @param {RegExp} filter - Regular expression to match the file name.
 * @return {Promise<Array<string>>} Promise resolving to an array of file paths.
 */
async function searchFileInDirectory(startPath, filter){
    let results = [];
    const files = await fs.readdir(startPath);
    const tasks = files.map(async (file) => {
        const filename = path.join(startPath, file);
        const stat = await fs.lstat(filename);
        if(stat.isDirectory()){
            const subDirResults = await searchFileInDirectory(filename, filter);
            results = results.concat(subDirResults);
        }
        else if(filter.test(filename)) results.push(filename);
    });

    // Wait for all tasks to complete
    await Promise.all(tasks);

    return results;
}

/**
 * Check if a Notification Service Extension is present and that there is only one.
 * @param {Object} targets - Targets from the Xcode project.
 */
function checkNotificationServiceExtension(targets) {
    let extensionCount = 0;

    for (let key in targets) {
        const target = targets[key];
        if (target && target.productType === "com.apple.product-type.app-extension") {
            extensionCount++;
        }
    }

    if (extensionCount > 1) {
        console.log("❌ Multiple Notification Service Extensions found. Only one should be present.");
    } else if (extensionCount === 1) {
        console.log("✅ Notification Service Extension found.");
    } else {
        console.log("❌ Notification Service Extension not found.");
    }
}

// Get root path
const rootPath = process.argv[2];

// Define the patterns to search for
const projPattern = /\.pbxproj$/;
const appDelegatePattern = /AppDelegate\.swift$/;

async function checkProject() {
    // Search for the .pbxproj and AppDelegate.swift files
    console.log("🔎 Searching for project files...");
    const [projectPaths, appDelegatePaths] = await Promise.all([
        searchFileInDirectory(rootPath, projPattern),
        searchFileInDirectory(rootPath, appDelegatePattern)
    ]);

    // Process each .pbxproj file
    for (let projectPath of projectPaths) {
        const project = xcode.project(projectPath);
        project.parseSync();

        console.log(`🔎 Checking project at path: ${projectPath}`);

        const targets = project.pbxNativeTargetSection();

        // Check for Notification Service Extension
        checkNotificationServiceExtension(targets);
    }

    // Process each AppDelegate.swift file
    for (let appDelegatePath of appDelegatePaths) {
        console.log(`🔎 Checking AppDelegate at path: ${appDelegatePath}`);
        try {
            const contents = await fs.readFile(appDelegatePath, 'utf8');
            if (contents.includes("func userNotificationCenter(")) {
                console.log("✅ Required method found in AppDelegate.swift");
            } else {
                console.log("❌ Required method not found in AppDelegate.swift");
            }
        } catch(err) {
            console.error("🚨 Error reading file:", err);
        }
    }
}

checkProject().catch(err => console.error("🚨 Error during project check:", err));
