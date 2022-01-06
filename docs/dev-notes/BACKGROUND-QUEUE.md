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
    switch result {
        case .success: 
            // yay! Profile identified! 
        case .failure(let cioError): 
            // Handle failure. Determine what failed and why. 
            // Write custom code to maybe retry the request later. 
    }   
}
```

With a queue, we can design our SDK to be similar to this:

```swift 
CustomerIO.shared.identify("Dana")
```

## How do I QA test the background queue? 

See [the QA doc](QA.md) in the background queue section. 

## How is the background queue built? 

The queue has a few main concepts. 

* Adding a task to the queue. 

Tasks need to be saved to persistent storage on the device to be able to run the task later on. We save .json files on the file system for the queue. We choose JSON simply because it's an easy way to save/read Swift objects to files. 

To be memory efficient, the queue data structure (aka: queue inventory) is saved in 1 JSON file. This inventory is general metadata about the tasks in the queue (see file `QueueTaskMetadata`). Then, each task of the queue is stored in it's own individual JSON file. 

Here is an idea of the file system structure where the queue has 2 tasks in it:

```
Documents/
  io.customer.ios/
    queue/
      inventory.json
      tasks/
        3838383949849493939393.json
        2939929292001919202002.json
```

After a task in the queue executes successfully, the queue will update the `inventory.json` file and will delete the task's `.json` file in `tasks/`. See `QueueStorage.swift` to view all the file system operations performed by the queue. 

Learn more by visiting files `Queue.swift` and `QueueStorage.swift`.

* Trigger the queue to run in the future. 

The queue is set to automatically run under these criteria:
* When a task is added to the queue, if there are now 10+ tasks in the queue, run the queue. 
* After a task is added to the queue, start a timer for 30 seconds. Run the queue after the 30 seconds is up. 

When either of these criteria is hit, the queue will execute. There is only 1 queue instance running at a time across the SDK. 

Learn more by visiting files `Queue.swift`.

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

See file `QueueQueryRunner` to learn more about how the queue gets the next task to execute and how it skips tasks by group. 

Learn more by visiting files `QueueRunRequest.swift` and `QueueRequestManager.swift`.


