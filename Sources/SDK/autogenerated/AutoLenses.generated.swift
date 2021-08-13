// Generated using Sourcery 1.5.0 — https://github.com/krzysztofzablocki/Sourcery
// DO NOT EDIT
// swiftlint:disable all

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
                                                        SdkConfig(siteId: siteId, apiKey: existing.apiKey, region: existing.region, devMode: existing.devMode)
                                                    })
    static let apiKeyLens = Lens<SdkConfig, String>(get: { $0.apiKey },
                                                    set: { apiKey, existing in
                                                        SdkConfig(siteId: existing.siteId, apiKey: apiKey, region: existing.region, devMode: existing.devMode)
                                                    })
    static let regionLens = Lens<SdkConfig, Region>(get: { $0.region },
                                                    set: { region, existing in
                                                        SdkConfig(siteId: existing.siteId, apiKey: existing.apiKey, region: region, devMode: existing.devMode)
                                                    })
    static let devModeLens = Lens<SdkConfig, Bool>(get: { $0.devMode },
                                                   set: { devMode, existing in
                                                       SdkConfig(siteId: existing.siteId, apiKey: existing.apiKey, region: existing.region, devMode: devMode)
                                                   })

    // Convenient set functions to edit a property of the immutable object
    func siteIdSet(_ siteId: String) -> SdkConfig {
        SdkConfig(siteId: siteId, apiKey: apiKey, region: region, devMode: devMode)
    }

    func apiKeySet(_ apiKey: String) -> SdkConfig {
        SdkConfig(siteId: siteId, apiKey: apiKey, region: region, devMode: devMode)
    }

    func regionSet(_ region: Region) -> SdkConfig {
        SdkConfig(siteId: siteId, apiKey: apiKey, region: region, devMode: devMode)
    }

    func devModeSet(_ devMode: Bool) -> SdkConfig {
        SdkConfig(siteId: siteId, apiKey: apiKey, region: region, devMode: devMode)
    }
}
