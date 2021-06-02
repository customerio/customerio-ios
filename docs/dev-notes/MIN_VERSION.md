# Min Swift & iOS version

This project has a minimum Swift version and minimum iOS version that it supports. 

Follow instructions below if you need to increase the versions. Our CI server matrix has the responsibility of making sure that changes we make work. Use that as the source of successful change of version. 

# Increase Swift version

* ./hooks/pre-commit.sh swiftformat swift version
* Package.swift swift-tools version
* Remove older swift versions in CI test workflow. 
* Try deleting `Customer.io.xcodeproj` and see if CI server passes. Older versions of Swift do not require an xcodeproj so it may be deprecated in future versions of Swift. 
    * If need to keep this directory, perform a search in the project for "5.1" or whatever the min is currently set at and replace all instances of this to the new minimum. 
* README.md badge version

# Increase iOS version

* Package.swift platforms version
* If `Customer.io.xcodeproj` still exists, open in XCode and make sure that `CIO` and `SDKTests` targets iOS versions are set to min. 
* README.md badge version