# Sample apps 

# Create a new sample app 

* In Xcode, create a new iOS app. Put the iOS app in a new directory inside of `Apps/` directory of this repository. There are examples in this repository that you can reference. 

* [Setup code signing for this new iOS app](https://github.com/customerio/apple-code-signing#creating-a-new-ios-app). 

* Copy the files in `Apps/CocoaPods-FCM/fastlane/` into your new iOS sample app. These files are required in order for the CI server to compile the sample app. 

Go through each of the files and edit them to values that are correct for your new iOS app. 

* If your new sample app uses CocoaPods (it's preferred to use Swift Package Manager instead of CocoaPods but some sample apps need to use CocoaPods so we can test that environment), then copy the `Podfile` from `../Apps/CocoaPods-FCM/Podfile`. That file is designed to always install the SDK from the local copy of the SDK which is what all of our sample apps should be doing. 

* Open `../.github/workflows/build-sample-apps.yml`. In this file, you will see code that looks like this:

```yml
    ...
    matrix: # Use a matrix allowing us to build multiple apps in parallel. Just add an entry to the matrix and it will build! 
      sample-app: 
      - "Foo"
```

Add a new entry to this list. The value will be the new directory that you created inside of `Apps/`. For example, if the new iOS app you made is inside of: `Apps/CocoaPods-FCM/`, then add this entry to this file:

```yml
    ...
    matrix: # Use a matrix allowing us to build multiple apps in parallel. Just add an entry to the matrix and it will build! 
      sample-app: 
      - "CocoaPods-FCM"
```

When you make a pull request for the new sample app that you created, you should see this app get compiled by the CI server. 

