// File that Danger runs to catch potential errors during PR reviews: https://danger.systems/js/
import {message, danger, warn} from "danger"

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