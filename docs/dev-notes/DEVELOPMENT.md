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

Let's say that you make changes to this project and you want your changes to become part of the project. This is the workflow that we follow to make that happen:

1. Make a new git branch where your changes will occur. 
2. Perform your changes on this branch. This part is very important. It's important that your git branches are focused with 1 goal in mind. 

Let's say that you decide to do all of this work under 1 git branch:
* Add a new feature to the app. 
* Fix a few bugs. 

....this is an anti-pattern in this repository. Instead...

* Make 1 git branch for your new feature that you add to the app. 
* Make 1 git branch for each bug that you fix. 

*Note: If you fix a bug or add a feature that it requires you edit the documentation, it's suggested to make all documentation changes in the git branch for that bug or feature. Not recommended to make separate branches just for documentation changes.*

Why do we do it this way? 
* It makes our git commit history cleaner. When you think to yourself, "Oh, what was that change I made 3 months ago?" you can more easily find those commits because they are focused. 
* It helps the team deploy the code more easily to customers. 
* It makes code reviews much easier as pull requests are now more focused. 
* It is easier to find what commits break code. When we make small pull requests, we are able to isolate those changes from each other and more easily find what changes cause what issues. 

3. Make a pull request. 

When you make a pull request, a team member will merge it for you after...
* All automated tests pass. If they don't it's your responsibility to fix them. 
* A team member will review your code. If they have suggestions on how to fix it, you can discuss the suggestions as a team and/or make changes to your code from those suggestions. 
* Make sure the title of the pull request follows the [conventional commit message](https://gist.github.com/levibostian/71afa00ddc69688afebb215faab48fd7) specification. 

### Deployment 

///