[url-tags]: https://github.com/customerio/customerio-ios/tags
[url-promote-action]: https://github.com/customerio/customerio-ios/actions/workflows/promote.yml

# Git Workflow 

This document goes over how we make branches, commits, and pull requests on this repository. We follow a specific workflow for this repository to make successful deployments for our customers. 

> Tip: If you have read this document already, you may want to [skip straight to the scenarios section](#Scenarios). 

# About the workflow 

This project follows [this popular workflow called `git-flow`](https://nvie.com/posts/a-successful-git-branching-model/). `git-flow` works well for this project because this project releases different versions of `alpha`, `beta`, and `production` versions of software to the public. Go ahead and [read over the `git-flow`](https://nvie.com/posts/a-successful-git-branching-model/) workflow to learn about the details of it. 

The [article you just read](https://nvie.com/posts/a-successful-git-branching-model/) shows you how you can manually run `git` commands on a repository to merge in new features, fix bugs, and make deployments. Our team might need to perform some manual tasks, but we try to automate running these `git` commands as much as possible. Automating these tasks helps to (1) avoid human error and (2) allows you to focus on simply writing code and avoid having to learn how to deploy the code. We try to keep this workflow as simple as possible by automating much of it. However, **if out automated tools ever encounter a problem and you need to manually fix the problem yourself, read the `git-flow` article to learn what `git` commands you need to run to fix the problem manually.**

Let's get into the many scenarios that you may encounter when working on this project and how you could do those tasks. 

## Deployment flow 

To understand this workflow, you need to understand how code is deployed. 

To help describe the deployment flow, refer to this image from the `git-flow` article:
![](https://nvie.com/img/git-model@2x.png)

There is a lot going on with this image. Let's try and explain it a little bit. 
* **2 permanent branches** - The branches `main` and `develop` are permanent branches and they never get deleted. `main` gets updated when a production deployment is made. `develop` is the default branch that code gets merged into that will be made into the next release of the software. 
* **Feature branches, bug fix branches, pre-release branches, etc** - All other branches (not `main` or `develop`) are temporary and get deleted after they have served their purpose. 
* **Make pull requests for all changes that you make to the project** - Any change that you make to the project should be merged into the project via a pull request on GitHub. That means that you should not be making commits to the branches: `develop`, `alpha`, `beta`, or `main`. 

* The *pink dots* on the left hand side are new features that you or your teammates are working on. You start a new feature by making a new branch off of the `develop` branch (or another feature branch if you need some code from that branch). It's important that new feature branches *do not* get created from release branches such as `alpha`, `beta`, or `main`. It's also important that new feature branches get merged into the `develop` branch, only. If your team made an `alpha` or `beta` release of your software yesterday and your new feature gets merged into `develop` today, your new feature should not get released until the current `alpha` or `beta` gets merged into production and then a new release is made in the future. 
* The *yellow dots* are commits on the develop branch. All pull requests and releases will eventually get merged into the `develop` branch. 
* The *green dots* are for a new release. Your team merged code into `main` last week which means that you made a production deployment on that day. Today, your team decides that the new code added to the `develop` branch should be released to the public. Maybe you added a new feature that you are wanting to ship. To start this release, you make a **pre-release** branch. On this team, that means that we make a new branch `alpha` off of the `develop` branch. Making this `alpha` branch will deploy a new alpha deployment of our software. 

When our team decides that it's time to promote the latest alpha release of our software to beta, a new branch `beta` is made off of the `alpha` branch and then the `alpha` branch gets deleted (remember, all branches except `main` and `develop` are temporary). When `beta` branch is made, a beta deployment gets deployed. 

> Note: Once a release has been started (when `alpha` or `beta` branch is created), only bug fixes should be merged into the release until it's in production. If you find a bug on the `alpha` or `beta` release, then you will make a new branch off of the `alpha` or `beta` branch and make a pull request with that fix back into `alpha` or `beta` branch. 

* The *red dots* are hotfix branches. Let's say that a customer finds a critical bug in one of our production releases. Our team may decide that we need to get this bug fixed as soon as possible and we decide to skip releasing this bug fix to `alpha` and `beta` and we deploy the bug fix immediately to production (after QA testing). To do that, you should make a new branch off of `main` (aka the latest production code), fix the bug, then make a pull request into `main`. When the pull request gets merged, there will be a new production deployment in production. 

* Finally *the blue dots* are git tags. Git tags [are all deployments][url-tags] that you have made for your software. When any release is made, a git tag gets made. 

With all of that explained, lets go over some common scenarios that you will encounter while working on this project. In fact, it might be a good idea to [click this link](#Scenarios) and then bookmark it in your browser so it's convenient. 

# Scenarios 

## Build a new feature 

Want to build a new feature? Here is how you would do that. 
1. Create a new branch for your feature. We like to name our branches `<your-name>/<feature-description>`. For example, if my name is Dana and I was to add a feature to allow customers to edit their photo on their profile, I would create a new branch `dana/edit-picture-profile`. Make this new branch off of the `develop` branch. 
2. Let's say that another member of your team, Bradley, is building a feature that allows users to upload photos in the app. You need that feature in your new feature you're working on for editing profile pictures. If you need this code, simply `git merge bradley/upload-photos` into your feature branch that you made. 
3. When you're done making this feature, make a pull request merging your branch *into the `develop` branch*. Features should *not* be merged into a release branch (`alpha`, `beta`, `main`). Your feature will be released to the public the next time that your team makes a release. 

## Fix a bug 

Where did you find this bug? 
* In an `alpha` or `beta` release of the software (the version of the release ends with `-alpha.X` or `-beta.X` such as `1.0.0-alpha.1`)? If so, make a new git branch off of the `alpha` or `beta` branch, fix the bug, then make a pull request merging your pull request into the `alpha` or `beta` branch. 
* In a production release of the software (the version of the release does *not* end with `-alpha.X` or `-beta.X` such as `1.0.0`)? If so, our team should make a decision on the bug. If this a bug that's not effecting a lot of customers? Is there a workaround we can help customers implement to temporary fix the bug? The team should decide if...
1. We can fix the bug and release it in the next release of our software (the bug will be merged into `develop` and then released to alpha and beta before production).
2. We need to provide a hot fix to customers. This is if the bug is more severe. This means we need to make a new branch off of `main`, fix the bug, then make a pull request into `main`. When the pull request gets merged, a new production release will be deployed to customers. 
* If the bug is in the `develop` branch and has not yet been released to customers in any way (alpha, beta, or production) then make a new branch off of `develop` and make a pull request into `develop`. 

## Make a new release 

### Want to make a new release of the project to Alpha? 
(Your project does *not* have a `alpha` or `beta` branch already and you want to make a new Alpha from the `develop` branch)

Follow these steps to promote using the recommended automated method:
* [Click this link][url-promote-action] > Run workflow > For "Use workflow from", select `develop` > Run. 

<details>
<summary>Did you encounter a problem with the automated release and you need to manually promote? Follow these steps:</summary>
<br>
* Run these `git` commands from your computer:

```bash
git fetch 

git switch develop
git pull 

git checkout -b alpha
git push origin alpha 
```

* Tell the team that you encountered an issue with making an automated release so it can be fixed. 
</details>

### Want to promote the latest alpha to beta? 
(There is an `alpha` branch in the project already that you want to promote to beta)

Follow these steps to promote using the recommended automated method:
* [Click this link][url-promote-action] > Run workflow > For "Use workflow from", select `alpha` > Run. 

<details>
<summary>Did you encounter a problem with the automated release and you need to manually promote? Follow these steps:</summary>
<br>
* Run these `git` commands from your computer:

```bash
git fetch 

git switch alpha
git pull 

git checkout -b beta
git push origin beta

git push origin --delete alpha 
```

* Tell the team that you encountered an issue with making an automated release so it can be fixed. 
</details>

### Want to promote the latest beta to production?** 
(Do you already have a beta released out to customers (there is an `beta` branch in the project already) that you want to promote to production)

Follow these steps to promote using the recommended automated method:
* [Click this link][url-promote-action] > Run workflow > For "Use workflow from", select `beta` > Run. 

<details>
<summary>Did you encounter a problem with the automated release and you need to manually promote? Follow these steps:</summary>
<br>
* Run these `git` commands from your computer:

```bash
git fetch 

git switch beta
git pull

git switch main
git pull 

git merge --ff beta 
git push origin main 

git push origin --delete beta 

git switch develop 
git pull 
git merge main
git push origin develop 
```

* Tell the team that you encountered an issue with making an automated release so it can be fixed. 
</details>

### Want to promote `develop` directly to Beta and skip Alpha? 
(Project does *not* contain `alpha` or `beta` branch already and you want to make a new Beta from the `develop` branch)

What is the use case for why you want to skip making an Alpha release and go straight to Beta? 

* Is it because you found a bug in production and you want to quickly release a fix? Follow the steps in [Fix a bug](#Fix-a-bug). 
* Is it because the project already has an Alpha released that you want to promote to Beta? Follow the steps in [Want to promote the latest alpha to beta?](#Want-to-promote-the-latest-alpha-to-beta)
* Any other reason? This is more then likely a red flag in a situation that we do not recommend that you do. You should probably follow the steps to make a new Alpha release from `develop`. 
Bring up to your team your use case for why you want to do this to see if it's a scenario that we should automate.

