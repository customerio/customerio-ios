// swiftlint:disable:next file_header
//
//  Middleware.swift
//  ReSwift
//
//  Created by Benji Encz on 12/24/15.
//  Copyright © 2015 ReSwift Community. All rights reserved.
//
//  Modifications made:
//  - Replaced Action with InAppMessageAction from Customer.io.
//  - Updated visibility to internal to prevent exposing non-public types.
//

typealias DispatchFunction = (InAppMessageAction) -> Void
typealias Middleware<State> = (@escaping DispatchFunction, @escaping () -> State?)
    -> (@escaping DispatchFunction) -> DispatchFunction
