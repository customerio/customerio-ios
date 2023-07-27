const xcode = require('xcode');
const path = require('path');
const fs = require('fs').promises;

/**
 * Search for a specific file within a directory and all its subdirectories.
 * @param {string} startPath - Path of the directory to start the search from.
 * @param {RegExp} filter - Regular expression to match the file name.
 * @return {Promise<Array<string>>} Promise resolving to an array of file paths.
 */
// Function to search a file in a directory and its subdirectories
async function searchFileInDirectory(startPath, filter) {
    let results = [];
    const files = await fs.readdir(startPath);
    const tasks = files.map(async (file) => {
        const filename = path.join(startPath, file);
        const stat = await fs.lstat(filename);

        // Skip the Pods directory and its subdirectories
        if (filename.includes('/Pods/')) return;

        if (stat.isDirectory()) {
            const subDirResults = await searchFileInDirectory(filename, filter);
            results = results.concat(subDirResults);
        }
        else if (filter.test(filename)) results.push(filename);
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
    let isEmbedded = false;
    let isFoundationExtension = false;

    for (let key in targets) {
        const target = targets[key];
        // The following check ensures that we are dealing with a valid 'target' that is an app extension.
        // 'target' and 'target.productType' must exist (i.e., they are truthy).
        // We then remove any single or double quotes and any leading or trailing whitespace from 'target.productType'.
        // If it matches "com.apple.product-type.app-extension", we increment the 'extensionCount'.

        if (target && target.productType && cleanString(target.productType) === "com.apple.product-type.app-extension") {
            console.log(`🔎 Found NSE: ${target.name}`);
            extensionCount++;
        }

        if (target && target.productType && cleanString(target.productType) === "com.apple.product-type.application") {
            console.log(`🔎 Checking if the NSE is embedded into target app: ${target.productType}`);
            // Check if the target is listed in the Embed App Extensions build phase.
            if (target.buildPhases && target.buildPhases.find((phase) => cleanString(phase.comment) === "Embed App Extensions")) {
                isEmbedded = true;
            } else if (target.buildPhases && target.buildPhases.find((phase) => cleanString(phase.comment) === "Embed Foundation Extensions")) {
                isFoundationExtension = true;
            }
        }
    }

    if (extensionCount > 1) {
        console.log("❌ Multiple Notification Service Extensions found. Only one should be present.");
    } else if (extensionCount === 1) {
        if (isEmbedded) {
            console.log("✅ Notification Service Extension found and embedded.");
        } else if (isFoundationExtension) {
            console.log("✅ Notification Service Extension found but not embedded as it is a Foundation Extension.");
        } else {
            console.log("❌ Notification Service Extension found but not embedded.");
        }
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
        } catch (err) {
            console.error("🚨 Error reading file:", err);
        }
    }
}

function cleanString(input) {
    return input.replace(/['"]/g, '').trim();
}

checkProject().catch(err => console.error("🚨 Error during project check:", err));
