// swiftlint:disable:next file_header
//
//  Reducer.swift
//  ReSwift
//
//  Created by Benjamin Encz on 12/14/15.
//  Copyright © 2015 ReSwift Community. All rights reserved.
//
//  Modifications made:
//  - Replaced Action with InAppMessageAction from Customer.io.
//  - Updated visibility to internal to prevent exposing non-public types.
//

typealias Reducer<ReducerStateType> =
    (_ action: InAppMessageAction, _ state: ReducerStateType?) -> ReducerStateType
