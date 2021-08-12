// Generated using Sourcery 1.5.0 — https://github.com/krzysztofzablocki/Sourcery
// DO NOT EDIT
// swiftlint:disable variable_name
// swiftlint:disable trailing_newline

import Foundation

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

extension SdkConfig {
    static let siteIdLens = Lens<SdkConfig, String>(get: { $0.siteId },
                                                    set: { siteId, existing in
                                                        SdkConfig(siteId: siteId, apiKey: existing.apiKey, regionCode: existing.regionCode)
                                                    })
    static let apiKeyLens = Lens<SdkConfig, String>(get: { $0.apiKey },
                                                    set: { apiKey, existing in
                                                        SdkConfig(siteId: existing.siteId, apiKey: apiKey, regionCode: existing.regionCode)
                                                    })
    static let regionCodeLens = Lens<SdkConfig, String>(get: { $0.regionCode },
                                                        set: { regionCode, existing in
                                                            SdkConfig(siteId: existing.siteId, apiKey: existing.apiKey, regionCode: regionCode)
                                                        })

    // Convenient set functions to edit a property of the immutable object
    func siteIdSet(_ siteId: String) -> SdkConfig {
        SdkConfig(siteId: siteId, apiKey: apiKey, regionCode: regionCode)
    }

    func apiKeySet(_ apiKey: String) -> SdkConfig {
        SdkConfig(siteId: siteId, apiKey: apiKey, regionCode: regionCode)
    }

    func regionCodeSet(_ regionCode: String) -> SdkConfig {
        SdkConfig(siteId: siteId, apiKey: apiKey, regionCode: regionCode)
    }
}
