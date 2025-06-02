// File that Danger runs to catch potential errors during PR reviews: https://danger.systems/js/
import {message, danger, warn} from "danger"
import {readFileSync} from "fs"

// Warn about possible breaking changes being introduced in a pull request. 
// Breaking changes should be documented when making a pull request. This is a reminder. 
let modifiedPublicApiFiles = danger.git.modified_files.filter((filePath) => filePath.endsWith("APITest.swift"))
modifiedPublicApiFiles.forEach((filePath) => {
  const message = `
I noticed file \`${filePath}\` was modified. That could mean that this pull request is introducing a *breaking change* to the SDK. 
  
If this pull request *does* introduce a breaking change, make sure the pull request title is in the format: 
\`\`\` 
<type>!: description of breaking change 
// Example:
refactor!: remove onComplete callback from async functions 
\`\`\`
  `

  warn(message)
})

// The SDK is deployed to multiple dependency management softwares (Cocoapods and Swift Package Manager). 
// This code tries to prevent forgetting to update metadata files for one but not the other. 
let isSPMFilesModified = danger.git.modified_files.includes('Package.swift') 
let isCococapodsFilesModified = danger.git.modified_files.filter((filePath) => filePath.endsWith('.podspec')).length > 0

console.log(`SPM files modified: ${isSPMFilesModified}, CocoaPods: ${isCococapodsFilesModified}`)

if (isSPMFilesModified || isCococapodsFilesModified) {
  if (!isSPMFilesModified) { warn("Cocoapods files (*.podspec) were modified but Swift Package Manager files (Package.*) files were not. This is error-prone when updating dependencies in one service but not the other. Double-check that you updated all of the correct files.") }
  if (!isCococapodsFilesModified) { warn("Swift Package Manager files (Package.*) were modified but Cocoapods files (*.podspec) files were not. This is error-prone when updating dependencies in one service but not the other. Double-check that you updated all of the correct files.") }
}

// Check Firebase/FCM version consistency between Package.swift and CustomerIOMessagingPushFCM.podspec
function checkFirebaseVersionConsistency() {
  try {
    // Read Package.swift and extract Firebase version range
    const packageSwiftContent = readFileSync('Package.swift', 'utf8')
    const firebasePackageMatch = packageSwiftContent.match(/\.package\(name: "Firebase".*?"(\d+\.\d+\.\d+)"\.\.< *"(\d+\.\d+\.\d+)"\)/)
    
    if (!firebasePackageMatch) {
      warn("Could not parse Firebase version range from Package.swift")
      return
    }
    
    const spmMinVersion = firebasePackageMatch[1]
    const spmMaxVersion = firebasePackageMatch[2]
    
    // Read CustomerIOMessagingPushFCM.podspec and extract FirebaseMessaging version range
    const podspecContent = readFileSync('CustomerIOMessagingPushFCM.podspec', 'utf8')
    const firebaseDepMatch = podspecContent.match(/spec\.dependency "FirebaseMessaging", ">= (\d+\.\d+\.\d+)", "< (\d+\.\d+\.\d+)"/)
    
    if (!firebaseDepMatch) {
      warn("Could not parse FirebaseMessaging version range from CustomerIOMessagingPushFCM.podspec")
      return
    }
    
    const podspecMinVersion = firebaseDepMatch[1]
    const podspecMaxVersion = firebaseDepMatch[2]
    
    // Compare versions
    if (spmMinVersion !== podspecMinVersion) {
      warn(`Firebase minimum version mismatch! Package.swift: ${spmMinVersion}, CustomerIOMessagingPushFCM.podspec: ${podspecMinVersion}`)
    }
    
    if (spmMaxVersion !== podspecMaxVersion) {
      warn(`Firebase maximum version mismatch! Package.swift: ${spmMaxVersion}, CustomerIOMessagingPushFCM.podspec: ${podspecMaxVersion}`)
    }
    
    if (spmMinVersion === podspecMinVersion && spmMaxVersion === podspecMaxVersion) {
      message(`✅ Firebase version bounds are consistent: ${spmMinVersion} to ${spmMaxVersion}`)
    }
  } catch (error) {
    warn(`Error checking Firebase version consistency: ${error.message}`)
  }
}

// Run the Firebase version consistency check
checkFirebaseVersionConsistency()