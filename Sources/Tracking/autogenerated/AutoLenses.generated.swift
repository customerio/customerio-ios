// Generated using Sourcery 1.5.0 — https://github.com/krzysztofzablocki/Sourcery
// DO NOT EDIT
// swiftlint:disable all

import Foundation

/**
 ######################################################
 Documentation
 ######################################################

 This automatically generated file you are viewing is to modify immutable objects in a convenient way.

 * What do you mean modify immutable objects? https://apiumhub.com/tech-blog-barcelona/lenses-swift-immutability-objects/

 * How do I use this?

 ```
 // Add `AutoLenses` protocol to struct.
 struct Foo: AutoLenses {
   // properties be `let` to be immutable
   let bar: String
   let bar2: Bool
 }

 var foo = Foo(bar: "X", bar2: true)
 // Now, we want to modify `foo.bar` but it's immutable. How do I modify `bar` without having to do something messy like...
 Foo(bar: "new value", bar2: oldInstance.bar2)
 ...to leave my other properties alone?

 foo = foo.setBar("new value")
 // Now, `foo` is set to the brand new instanced of `Foo` while copying over all other values of `Foo` from the old instance.
 ```

 */

infix operator *~: MultiplicationPrecedence
infix operator |>: AdditionPrecedence

struct Lens<Whole, Part> {
    let get: (Whole) -> Part
    let set: (Part, Whole) -> Whole
}

func * <A, B, C>(lhs: Lens<A, B>, rhs: Lens<B, C>) -> Lens<A, C> {
    Lens<A, C>(get: { a in rhs.get(lhs.get(a)) },
               set: { c, a in lhs.set(rhs.set(c, lhs.get(a)), a) })
}

func *~ <A, B>(lhs: Lens<A, B>, rhs: B) -> (A) -> A {
    { a in lhs.set(rhs, a) }
}

func |> <A, B>(x: A, f: (A) -> B) -> B {
    f(x)
}

func |> <A, B, C>(f: @escaping (A) -> B, g: @escaping (B) -> C) -> (A) -> C {
    { g(f($0)) }
}

extension QueueTask {
    static let storageIdLens = Lens<QueueTask, String>(get: { $0.storageId },
                                                       set: { storageId, existing in
                                                           QueueTask(storageId: storageId, type: existing.type,
                                                                     data: existing.data,
                                                                     runResults: existing.runResults)
                                                       })
    static let typeLens = Lens<QueueTask, QueueTaskType>(get: { $0.type },
                                                         set: { type, existing in
                                                             QueueTask(storageId: existing.storageId, type: type,
                                                                       data: existing.data,
                                                                       runResults: existing.runResults)
                                                         })
    static let dataLens = Lens<QueueTask, Data>(get: { $0.data },
                                                set: { data, existing in
                                                    QueueTask(storageId: existing.storageId, type: existing.type,
                                                              data: data, runResults: existing.runResults)
                                                })
    static let runResultsLens = Lens<QueueTask, QueueTaskRunResults>(get: { $0.runResults },
                                                                     set: { runResults, existing in
                                                                         QueueTask(storageId: existing.storageId,
                                                                                   type: existing.type,
                                                                                   data: existing.data,
                                                                                   runResults: runResults)
                                                                     })

    // Convenient set functions to edit a property of the immutable object
    func storageIdSet(_ storageId: String) -> QueueTask {
        QueueTask(storageId: storageId, type: type, data: data, runResults: runResults)
    }

    func typeSet(_ type: QueueTaskType) -> QueueTask {
        QueueTask(storageId: storageId, type: type, data: data, runResults: runResults)
    }

    func dataSet(_ data: Data) -> QueueTask {
        QueueTask(storageId: storageId, type: type, data: data, runResults: runResults)
    }

    func runResultsSet(_ runResults: QueueTaskRunResults) -> QueueTask {
        QueueTask(storageId: storageId, type: type, data: data, runResults: runResults)
    }
}

extension QueueTaskRunResults {
    static let totalRunsLens = Lens<QueueTaskRunResults, Int>(get: { $0.totalRuns },
                                                              set: { totalRuns, existing in
                                                                  QueueTaskRunResults(totalRuns: totalRuns)
                                                              })

    // Convenient set functions to edit a property of the immutable object
    func totalRunsSet(_ totalRuns: Int) -> QueueTaskRunResults {
        QueueTaskRunResults(totalRuns: totalRuns)
    }
}

extension SdkCredentials {
    static let apiKeyLens = Lens<SdkCredentials, String>(get: { $0.apiKey },
                                                         set: { apiKey, existing in
                                                             SdkCredentials(apiKey: apiKey, region: existing.region)
                                                         })
    static let regionLens = Lens<SdkCredentials, Region>(get: { $0.region },
                                                         set: { region, existing in
                                                             SdkCredentials(apiKey: existing.apiKey, region: region)
                                                         })

    // Convenient set functions to edit a property of the immutable object
    func apiKeySet(_ apiKey: String) -> SdkCredentials {
        SdkCredentials(apiKey: apiKey, region: region)
    }

    func regionSet(_ region: Region) -> SdkCredentials {
        SdkCredentials(apiKey: apiKey, region: region)
    }
}
