# Customer.io iOS SDK

Official Customer.io SDK for iOS

# Why use the Customer.io SDK?

* [X] Official SDK from Customer.io for iOS. 
///

# Getting started

///

# Documentation

//

# Contributing

Thank you for your interest in wanting to contribute to the project! Let's get your development environment setup so you can get developing.

Follow each section below to get the code running successfully on your machine. 

### Development getting started

* Feel free to use any text editor that you wish to work on this project. XCode is not required for this project. However, if you wish to use XCode, rick click on the `Package.swift` file in this project > Open with > XCode. XCode will then import this project into XCode. You will be able to compile the code and run tests within XCode. 

* Install git hooks on your machine for performing development tasks: 

```
$> ./hooks/autohook.sh install
[Autohook] Scripts installed into .git/hooks
```

After installing hooks, you will see some output about installing tools. Follow those instructions to install some development tools the hooks use. 

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

# License

[MIT](LICENSE)