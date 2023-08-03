const xcode = require('xcode');
const path = require('path');
const fs = require('fs').promises;

/**
 * Function to clean a string by removing single/double quotes and leading/trailing whitespaces.
 * @param {string} input - String to be cleaned.
 * @return {string} Cleaned string.
 */
function cleanString(input) {
    return input.replace(/['"]/g, '').trim();
}

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
            console.log(`🔎 Found extension app: ${JSON.stringify(target)}`);
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

function getDeploymentTargetVersion(pbxProject) {
    const buildConfig = pbxProject.pbxXCBuildConfigurationSection();
    const nativeTargets = pbxProject.pbxNativeTargetSection();
    const configList = pbxProject.pbxXCConfigurationList();

    let nseBuildConfigKeys = [];

    // Find the NSE build configuration list key
    for (let key in nativeTargets) {
        const nativeTarget = nativeTargets[key];
        if (nativeTarget.productType && cleanString(nativeTarget.productType) === 'com.apple.product-type.app-extension') {
            const configListKey = nativeTarget.buildConfigurationList;
            const buildConfigurations = configList[configListKey].buildConfigurations;
            nseBuildConfigKeys = buildConfigurations.map(config => config.value);
            break;
        }
    }

    // Return deployment target of the NSE
    if (nseBuildConfigKeys.length) {
        for (let key in buildConfig) {
            const config = buildConfig[key];
            // Check if the config is the NSE build configuration and it has an iOS deployment target
            if (nseBuildConfigKeys.includes(key) && config.buildSettings && config.buildSettings['IPHONEOS_DEPLOYMENT_TARGET']) {
                return config.buildSettings['IPHONEOS_DEPLOYMENT_TARGET'];
            }
        }
    }

    return null;
}

// Validate input argument
if (!process.argv[2]) {
    console.error("🚨 Error: No directory provided.");
    process.exit(1);
}

// Get root path
const rootPath = process.argv[2];

// Define the patterns to search for
const projPattern = /\.pbxproj$/;
const appDelegateSwiftPattern = /AppDelegate\.swift$/;
const appDelegateObjectiveCPattern = /AppDelegate\.mm$/;
const entitlementsFilePattern = /\.entitlements$/;

const objCUserNotificationCenterPattern = /-\s?\(void\)userNotificationCenter:\s*\(UNUserNotificationCenter\s?\*\)center\s*/;;
const pushNotificationEntitlementPattern = /<key>\s*aps-environment\s*<\/key>/;

async function checkProject() {
    // Search for the .pbxproj and AppDelegate.swift files
    console.log("🔎 Searching for project files...");

    const iosProjectPath = path.join(rootPath, 'ios');
    const [projectPaths, appDelegateSwiftPaths, appDelegateObjectiveCPaths, entitlementsFilePaths] = await Promise.all([
        searchFileInDirectory(iosProjectPath, projPattern),
        searchFileInDirectory(iosProjectPath, appDelegateSwiftPattern),
        searchFileInDirectory(iosProjectPath, appDelegateObjectiveCPattern),
        searchFileInDirectory(iosProjectPath, entitlementsFilePattern),
    ]);

    // Process each .pbxproj file
    for (let projectPath of projectPaths) {
        const project = xcode.project(projectPath);
        project.parseSync();

        console.log(`🔎 Checking project at path: ${projectPath}`);

        const targets = project.pbxNativeTargetSection();

        // Check for Notification Service Extension
        checkNotificationServiceExtension(targets);

        const deploymentTarget = getDeploymentTargetVersion(project);
        console.log(`🔔 Deployment Target Version for NSE: ${deploymentTarget}. Ensure this version is not higher than the iOS version of the devices where the app will be installed. A higher target version may prevent some features, like rich notifications, from working correctly.`);
    }

    // Process each AppDelegate.swift file
    for (let appDelegatePath of appDelegateSwiftPaths) {
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

    // Process each AppDelegate.m file
    for (let appDelegatePath of appDelegateObjectiveCPaths) {
        console.log(`🔎 Checking AppDelegate at path: ${appDelegatePath}`);
        try {
            const contents = await fs.readFile(appDelegatePath, 'utf8');
            if (objCUserNotificationCenterPattern.test(contents)) {
                console.log("✅ Required method found in AppDelegate.m");
            } else {
                console.log("❌ Required method not found in AppDelegate.m");
            }
        } catch (err) {
            console.error("🚨 Error reading file:", err);
        }
    }

    // Process each entitlements file
    for (let entitlementsFilePath of entitlementsFilePaths) {
        console.log(`🔎 Checking entitlements file at path: ${entitlementsFilePath}`);
        try {
            // We can use XML parsing libraries (like xml2js) for better results because entitlements files are XML files
            const contents = await fs.readFile(entitlementsFilePath, 'utf8');
            if (pushNotificationEntitlementPattern.test(contents)) {
                console.log("✅ Push Notification capability found in entitlements");
            } else {
                console.log("❌ Push Notification capability not found in entitlements");
            }
        } catch (err) {
            console.error("🚨 Error reading file:", err);
        }
    }
}

checkProject().catch(err => console.error("🚨 Error during project check:", err));
