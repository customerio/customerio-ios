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
