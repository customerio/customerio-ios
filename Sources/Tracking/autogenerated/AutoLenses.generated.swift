// Generated using Sourcery 1.9.2 — https://github.com/krzysztofzablocki/Sourcery
// DO NOT EDIT
// swiftlint:disable all

import Common
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
    Lens<A, C>(
        get: { a in rhs.get(lhs.get(a)) },
        set: { c, a in lhs.set(rhs.set(c, lhs.get(a)), a) }
    )
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
