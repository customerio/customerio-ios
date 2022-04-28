# Background queue 

## What is the background queue? 

Anytime that the SDK needs to perform any asynchronous operation (such as a HTTP request), the SDK will simply add the task to a queue and run the task at a later time instead of running the operation right away. 

By running tasks at a later time, there are many great benefits. 
1. The SDK performs error handling and retries tasks later instead of the customer needing to do it. 
2. The SDK is much more powerful now that we can add any task to the queue
3. We can provide offline functionality to our SDK. 
4. We save battery on the device because we batch network requests together. 
5. We can provide a better design of the SDK functions for customers. 

Instead of designing our SDK to be asynchronous like this:

```swift
CustomerIO.shared.identify("Dana") { result in 
    // handle the result. If success or error 
    switch (result) {
        ...
    }   
}
```

With a queue, we can design our SDK to be similar to this:

```swift
// no need to handle the result! SDK does it for you!
CustomerIO.shared.identify("Dana")
```

## How do I QA test the background queue? 

See [the QA doc](QA.md) in the background queue section. 

## How is the background queue built? 

The queue has a few main concepts. 

* Adding a task to the queue. 

To be able to run the queue task later on, they need to be saved to persistent storage on the device. We save `.json` files on the file system for the queue. We choose JSON simply because it's an easy way to save/read objects to files. 

To be memory efficient, the queue data structure (aka: queue inventory) is saved in 1 JSON file. This inventory is general metadata about the tasks in the queue (see file `QueueTaskMetadata`). Then, each task of the queue is stored in it's own individual JSON file. 

Here is an idea of the file system structure where the queue has 2 tasks in it:

```
Documents/
  io.customer/
    queue/
      inventory.json
      tasks/
        3838383949849493939393.json
        2939929292001919202002.json
```

After a task in the queue executes successfully, the queue will update the `inventory.json` file and will delete the task's `.json` file from the `tasks/` directory. See `QueueStorage` to view all the file system operations performed by the queue. 

Learn more by visiting classes `Queue` and `QueueStorage`.

* Trigger the queue to run in the future. 

The queue is set to automatically run under these criteria:
* When a task is added to the queue, if there are now 10+ tasks in the queue, run the queue. 
* After a task is added to the queue, start a timer for 30 seconds. Run the queue after the 30 seconds is up. 

When either of these criteria is hit, the queue will execute. There is only 1 queue instance running at a time across the SDK. 

Learn more by visiting class `Queue`.

* Run the queue. 

When it's time to run the queue, here are the operations of the queue:
1. Take a snapshot of the queue inventory. Read the whole JSON file, grab the first task of the queue, execute that asynchronous operation. 
2. If the task succeeds, delete the task from the file system and inventory,  move to the next task of the queue, go back to step 1 above. 
3. If the task fails to run, the queue will check if the task that failed is the start of a *task group*. If it is *not* the start, the queue will simply behave as normal where it goes to the next task of the queue and executes it. if the task *is* the start of a task group, the queue will skip executing all members of that task group left in the queue. 

What is a task group? Let's say the queue has these items in it:
A. identify profile A - the API has never created profile A before.
B. track event for profile A
C. push metric opened for push notification Z

[![](https://mermaid.ink/img/eyJjb2RlIjoiZmxvd2NoYXJ0IFREXG5cbkFbQXNzdW1pbmcgdGhlIHF1ZXVlIGNvbnRhaW5zIHRoZSB0YXNrcyA8YnIvPiBBLCBCLCBhbmQgQyA8YnIvPiB3aGVyZSBBIGFuZCBCIGFyZSBpbiBhIHRhc2sgZ3JvdXAgdG9nZXRoZXIuIDxici8-PGJyLz4gUXVldWUgcnVucyB0YXNrIEFdIC0tPnxEaWQgdGFzayBydW4gc3VjY2Vzc2Z1bGx5P3wgQnt5ZXN9ICYgQ3tub31cbkIgLS0-IEQoUnVuIHRhc2sgQilcbkMgLS0-IHxJcyB0YXNrIEEgdGhlIHN0YXJ0IG9mIGEgdGFzayBncm91cD98IEV7eWVzfSAmIEZ7bm99XG5GIC0tPiBIKFJ1biB0YXNrIEIpXG5FIC0tPiB8U2tpcCBhbGwgdGFza3MgdGhhdCBiZWxvbmcgdG8gdGhlIHRhc2sgZ3JvdXAuIDxici8-IFJ1biBuZXh0IHRhc2sgaW4gcXVldWUgdGhhdCBkb2VzIG5vdCBiZWxvbmcgdG8gdGhhdCBncm91cC58IEcoU2tpcCB0YXNrIEIuIFJ1biB0YXNrIEMpIiwibWVybWFpZCI6eyJ0aGVtZSI6ImRlZmF1bHQifSwidXBkYXRlRWRpdG9yIjpmYWxzZSwiYXV0b1N5bmMiOnRydWUsInVwZGF0ZURpYWdyYW0iOmZhbHNlfQ)](https://mermaid-js.github.io/mermaid-live-editor/edit#eyJjb2RlIjoiZmxvd2NoYXJ0IFREXG5cbkFbQXNzdW1pbmcgdGhlIHF1ZXVlIGNvbnRhaW5zIHRoZSB0YXNrcyA8YnIvPiBBLCBCLCBhbmQgQyA8YnIvPiB3aGVyZSBBIGFuZCBCIGFyZSBpbiBhIHRhc2sgZ3JvdXAgdG9nZXRoZXIuIDxici8-PGJyLz4gUXVldWUgcnVucyB0YXNrIEFdIC0tPnxEaWQgdGFzayBydW4gc3VjY2Vzc2Z1bGx5P3wgQnt5ZXN9ICYgQ3tub31cbkIgLS0-IEQoUnVuIHRhc2sgQilcbkMgLS0-IHxJcyB0YXNrIEEgdGhlIHN0YXJ0IG9mIGEgdGFzayBncm91cD98IEV7eWVzfSAmIEZ7bm99XG5GIC0tPiBIKFJ1biB0YXNrIEIpXG5FIC0tPiB8U2tpcCBhbGwgdGFza3MgdGhhdCBiZWxvbmcgdG8gdGhlIHRhc2sgZ3JvdXAuIDxici8-IFJ1biBuZXh0IHRhc2sgaW4gcXVldWUgdGhhdCBkb2VzIG5vdCBiZWxvbmcgdG8gdGhhdCBncm91cC58IEcoU2tpcCB0YXNrIEIuIFJ1biB0YXNrIEMpIiwibWVybWFpZCI6IntcbiAgXCJ0aGVtZVwiOiBcImRlZmF1bHRcIlxufSIsInVwZGF0ZUVkaXRvciI6ZmFsc2UsImF1dG9TeW5jIjp0cnVlLCJ1cGRhdGVEaWFncmFtIjpmYWxzZX0)

*Tip: Click the flowchart to open up an editor to make edits to it. Update markdown above with your changes.*

> Explaination of chart: If the queue task A fails to execute, queue task B will fail as well. Why? Because the API has yet to create profile A so we can't track events to profile A. The API will always return a 4xx status code until task A is successful. To fix this issue, we created *task groups*. If we put task A and B in the same task group where task A is the *start* of the task group and have task B be a member of that same group, then if task A fails to execute, the queue will then see task B is a member of that group and will then skip task B and move onto task C which is not a member of the task group. 

See class `QueueQueryRunner` to learn more about how the queue gets the next task to execute and how it skips tasks by group. 

Learn more by visiting class `QueueRunRequest`.

## What data is saved when a task is added to the background queue? 

The queue is only responsible for performing the network requests *after* the SDK has changed it's internal state (example: save a profile ID to local device storage for future SDK calls).

The queue runner tasks are all [small in logic where they just perform a HTTP request](https://github.com/customerio/customerio-android/blob/7e6b1d6724fd199b6a721e05a4726e48d6c19089/sdk/src/main/java/io/customer/sdk/queue/QueueRunner.kt#L39-L43). Not necessarily on purpose, but it just works out that way because you want to do all the local changes to the state of the SDK before running the task in the queue. 

The queue acts as a sync where it sends *snapshots of events* that have happened in the SDK to the API. For example, let's say that you have an app that allows you to modify the first name of your profile. After the app user changes their first name in the app, your app wants to send the edited first name to your remote API. Your app should do the following events:
1. Save the first name to local storage such as a database to act as a cache. This changes the local state of the app. 
2. Add a task to the background queue to eventually send the new first name to the remote API. It is at this time that you *provide to the background queue the new first name value* to be sent to the remote API. It's like you are taking a snapshot of the state of the SDK at this time and giving it to the background queue. You do not want to query the app's storage for the new first name when the background queue runs. You want to provide the actual first name value to the queue when you add the task. 

```swift
let profileId = 5 // the identifier to query our app's local data storage for this profile
let newFirstName = "Eddie"
database.updateFirstName(id: profileId, firstName: newFirstName)

// Do this:
backgroundQueue.addTask(
    "edit_profile",
    EditProfileQueueTaskData(newFirstName)
)

// Do *not* do this:
backgroundQueue.addTask(
    "edit_profile",
    EditProfileQueueTaskData(profileId) // when "edit_profile" task runs in the background queue, query the database for the first name for id 5
)
```

Why this is important is to avoid a scenario like this:
* Your first name in app is `Dana`. 
* You change your first name to `Eddie`. Add a task to background queue to update first name. 
* You change your first name **again** to `Frankie` **before the background queue runs**. Add **another** task to the background queue to update first name.
* Background queue now has 2 tasks in it. The queue runs task 1 to update first name. If you provided the value `Eddie` to the background queue at the time of adding the event to the queue, the queue at this point would know to send the value `Eddie` to the API. But if you didn't provide `Eddie` and you are instead relying on your app simply checking the current state of the app's cached data, the background queue would instead send the value `Frankie` to the API and would never send `Eddie`. Your remote API would never know about the value `Eddie`. 

In other words, once the background queue processes the tasks on your API you would receive two calls like the following if you provided the name values:
- `edit_profile first_name=Eddie`
- `edit_profile first_name=Frankie`
However if you pulled the latest cached value while sending then the event could look like:
- `edit_profile first_name=Frankie`
- `edit_profile first_name=Frankie`

For some use cases like the one above, this should not impose a threat to the state of your app or it's data. But what if you have a different use case that involves deleting? In a scenario like this, the background queue could result in a state where it would never succeed because the local cached data could have been deleted by the time the background queue runs. 

These examples might seem like they have simple solutions to solve them. But as projects grow, it quickly gets out of hand. Instead, if you use your background queue as a queue of snapshots of historical events of your app, the queue will always be in sync with the state of your app. 


