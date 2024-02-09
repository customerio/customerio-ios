# QA testing 

## Getting started QA testing the SDK

1. Make sure that the mobile app that you are testing with has SDK logging enabled. This is done with the following code:
```swift
CustomerIO.initialize(siteId: Env.customerIOSiteId, apiKey: Env.customerIOApiKey, region: region) { config in
    config.logLevel = .debug
}
```

*Note: Logs should already be turned on for you in the Remote Habits mobile app*

## Background queue 

First, it's recommended you read the section *What is the background queue?* from the [background queue](BACKGROUND-QUEUE.md) doc to understand an overview of what a background queue is. 

A background queue means that anytime that you perform an operation on the SDK such as identifying a customer, you will *not* see the change in `fly.customer.io` right away. You need to wait until the queue runs the task (and the task runs successfully) before you will see the change in the app. 

So, how do we expect the background queue to function in the SDK? 

Anytime that you perform a function of the SDK such as identifying a profile, tracking an event, tracking a push metric, opening a push notification, etc. you should expect to see a log statement being made by the SDK such as:

```
identify profile dana900
storing identifier on device storage dana900
adding queue task identifyProfile
added queue task data IdentifyProfile(identifier: "dana900")
processing queue status QueueStatus(numberOfTask: 5)
queue timer: scheduled to run queue in 30 seconds
```

This tells you that (1) the SDK was asked to identify a profile with an identifier "dana900" and that (2) the SDK added that operation to the background queue and the queue is scheduled to run in 30 seconds. 

The queue is setup to automatically run after a set of criteria is met:
* When a task is added to the queue, if there are now 10+ tasks in the queue, run the queue. 
* After a task is added to the queue, start a timer for 30 seconds. Run the queue after the 30 seconds is up. 

That means that you will need to meet one of these criteria before you will start the queue and then finally see your result in the web app. 

After the criteria has been met, you should see logs similar to:
```
queue timer: now running queue
queue run request sent
queue tasks left to run: 5 out of 5
queue next task to run: 38383838-383838383-49490495, identifyProfile, IdentifyProfile(identifier: "dana900")
queue task 38383838-383838383-49490495 ran successfully
queue deleting task 38383838-383838383-49490495
queue deleting task 38383838-383838383-49490495 success: true 
```

Now if you go into the web app, you should see a profile identified! 

If lets say you had a bad Internet connection, you are in airplane mode, or there is a bug in the SDK or mobile app code, then the SDK woud log:

```
queue task 38383838-383838383-49490495 fail - <error description here>
queue task 38383838-383838383-49490495 updating run history from numberOfTimesRun: 0 to numberOfTimesRun: 1
queue task 38383838-383838383-49490495 update success true 
... queue will move onto the next task to run...
```

You get the idea. The logs will tell you everything that you need to know about the queue running. 

The logs and HTTP requests are critical to debugging the queue so please be sure to save a copy of the HTTP requests performed and the SDK logs if you encounter something that isn't behaving as expected. 
