# Development Getting Started 

### Development getting started

* Open `Package.swift` file in XCode to open project. XCode knows how to open SPM projects from this file. Or, open this root directory in your favorite source code editor. 

* Install git hooks on your machine for performing development tasks: 

```
$> ./hooks/autohook.sh install
[Autohook] Scripts installed into .git/hooks
```

### Development tools 

* [SwiftLint](https://github.com/realm/SwiftLint) - Lints the Swift source code of the project. 

**How to run tool** Linting is done automatically for you with git hooks. When git hooks run, if it finds code that needs changed, you will see errors in your console. If you want to manually run, you can run `make lint` on your machine. 

**How to install** `brew install swiftlint`

* [SwiftFormat](https://github.com/nicklockwood/SwiftFormat) - Formats Swift code to a nice standard/common format. 

**How to run tool** Linting is done automatically for you with git hooks. If you want to manually run, you can run `make format` on your machine. 

**How to install** `brew install swiftformat`

* [Sourcery](https://github.com/krzysztofzablocki/Sourcery) - Generate boilerplate Swift code for project. We use this for generating our dependency injection graph and mocks to make testing easier. 

**How to run tool** You must run this tool manually. Run `make generate` on your machine to do so. You will want to run this command each time that you create a new class, for example. A good time is to always run it before you write your tests. Or, you can copy the command from the `Makefile` for `generate` command and add `--watch` to the command to generate automatically as you write code. 

**How to install** `brew install sourcery`

### Development workflow 

See file [GIT-WORKFLOW](GIT-WORKFLOW.md) to learn about the workflow that this project uses. 