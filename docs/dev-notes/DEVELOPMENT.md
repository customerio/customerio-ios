# Development Getting Started 

### Development getting started

* Open `Package.swift` file in XCode to open project. XCode knows how to open SPM projects from this file. Or, open this root directory in your favorite source code editor. 

* Setup git hooks using the tool [lefthook](https://github.com/evilmartians/lefthook):

```
$ brew install lefthook 
$ lefthook install 
SYNCING
SERVED HOOKS: pre-commit, prepare-commit-msg
```

### Development tools 

The SDK project leverages several CLI tools essential for Swift/iOS development. To ensure a consistent development environment, we use [binny](https://github.com/customerio/binny), a tool designed to streamline the installation and updating process of these development tools. Follow the steps below to get started:

* [Install `binny` from the instructions in the `binny` project](https://github.com/customerio/binny#get-started).
* Done! `binny` will automatically install the development tools for you when you need them later. 

### Generate boilerplate code 

Dependency injection graphs and mocks are automatically generated for you (See `*.generated.swift` files to see examples of what gets generated). Anytime that you modify code in the SDK project and you get compile time errors, it's probably because the generated files are out-of-date. Run `make generate` to generate the files. 