# Min Swift & iOS version

This project has a minimum Swift version and minimum iOS version that it supports. 

Follow instructions below if you need to increase the versions. Our CI server matrix has the responsibility of making sure that changes we make work. Use that as the source of successful change of version. 

# Increase Swift version

* `Makefile` swiftformat swift version
* Package.swift swift-tools version
* Remove older swift versions in CI test workflow. 
* README.md badge version
* Edit `cocoapods.podspec` file, line: `spec.swift_version = 'X.X'`

# Increase iOS version

* Package.swift platforms version
* README.md badge version
* Edit `cocoapods.podspec` file, line: `spec.ios.deployment_target = "X.X"`