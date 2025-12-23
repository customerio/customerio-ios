//
//  SynchronizedTests.swift
//  Customer.io
//
//  Created by Holly Schilling on 12/22/25.
//

import Testing
import Foundation

@testable
import CioInternalCommon


struct SynchronizedTests {
    
    @Test
    func testValueAccess() async throws {
        let initial = 31415
        let sync = Synchronized(initial: initial)
        
        #expect(sync.wrappedValue == initial)
    }
    
    @Test
    func testModifyingValue() async throws {
        let initial: Int = 31415
        let sync = Synchronized(initial: initial)
        
        sync.wrappedValue = 271828
        
        #expect(sync.wrappedValue == 271828)
    }
    
    @Test
    func testModifyingValueWithMutating() throws {
        let initial: Int = 31415
        let sync = Synchronized(initial: initial)

        #expect(sync.wrappedValue == initial)

        sync.mutating { value in
            value = 271828
        }
        
        #expect(sync.wrappedValue == 271828)
    }
    
    @Test
    func testAccessingValueFromUsing() throws {
        let initial: Int = 31415
        let sync = Synchronized(initial: initial)
        
        let fetched: Int = sync.using { $0 }
        
        #expect(fetched == initial)
    }
    
    @Test
    func testModifyingValueFromUsing() throws {
        let initial: Int = 31415
        let sync = Synchronized(initial: initial)
        
        let fetched: Int = sync.using {
            $0 + 1
        }
        #expect(sync.wrappedValue == 31415)
        #expect(fetched == 31416)
    }
    
    @Test
    func testBreakingThreadSafety() throws {
        let sync = Synchronized(initial: 0)
        
        let operationQueue = OperationQueue()
        operationQueue.isSuspended = true
        
        for _ in 0..<1_000_000 {
            operationQueue.addOperation {
                sync += 1
            }
        }
        operationQueue.isSuspended = false
        operationQueue.waitUntilAllOperationsAreFinished()
        
        #expect(sync.wrappedValue == 1_000_000)
    }
    
//MARK: - Integer Operation Extensions
    
    @Test
    func testPlusEqualsInteger() throws {
        let initial: Int = 31415
        let sync = Synchronized(initial: initial)
        
        sync += 1
        #expect(sync.wrappedValue == 31416)
    }
    
    @Test
    func testMinusEqualsInteger() throws {
        let initial: Int = 31415
        let sync = Synchronized(initial: initial)
        
        sync -= 1
        #expect(sync.wrappedValue == 31414)
    }
    
    @Test
    func testPlusEqualsSynchronizedInteger() throws {
        let initial1: Int = 31415
        let initial2: Int = 27182
        let sync1 = Synchronized(initial: initial1)
        let sync2 = Synchronized(initial: initial2)
        
        sync1 += sync2
        #expect(sync1.wrappedValue == 58597)
    }
    
    @Test
    func testMinusEqualsSynchronizedInteger() throws {
        let initial1: Int = 31415
        let initial2: Int = 27182
        
        let sync1 = Synchronized(initial: initial1)
        let sync2 = Synchronized(initial: initial2)
        
        sync1 -= sync2
        #expect(sync1.wrappedValue == 4233)
    }
    
    @Test
    func testPlusInteger() throws {
        let initial: Int = 31415
        let sync = Synchronized(initial: initial)
        
        let result: Int = sync + 1
        #expect(sync.wrappedValue == initial)
        #expect(result == 31416)
    }
    
    @Test
    func testMinusInteger() throws {
        let initial: Int = 31415
        let sync = Synchronized(initial: initial)
        
        let result: Int = sync - 1
        #expect(sync.wrappedValue == initial)
        #expect(result == 31414)
    }
    
    @Test
    func testPlusSynchronizedInteger() throws {
        let initial1: Int = 31415
        let initial2: Int = 27182
        let sync1 = Synchronized(initial: initial1)
        let sync2 = Synchronized(initial: initial2)
        
        let result: Int = sync1 + sync2
        #expect(sync1.wrappedValue == initial1)
        #expect(sync2.wrappedValue == initial2)
        #expect(result == 58597)
    }
    
    @Test
    func testMinusSynchronizedInteger() throws {
        let initial1: Int = 31415
        let initial2: Int = 27182
        let sync1 = Synchronized(initial: initial1)
        let sync2 = Synchronized(initial: initial2)
        
        let result: Int = sync1 - sync2
        #expect(sync1.wrappedValue == initial1)
        #expect(sync2.wrappedValue == initial2)
        #expect(result == 4233)
    }
    
//MARK: - Dictionary Operations
    
    @Test
    func testDictionarySubscriptGet() {
        let initial = [
            "foo": 1,
            "bar": 2,
        ]
        let sync = Synchronized(initial: initial)
        
        #expect(sync["foo"] == 1)
        #expect(sync["bar"] == 2)
    }
    
    @Test
    func testDictionarySubscriptSet() {
        let initial = [
            "foo": 1,
            "bar": 2,
        ]
        let sync = Synchronized(initial: initial)
        
        sync["foo"] = 3
        
        #expect(sync["foo"] == 3)
        #expect(sync["bar"] == 2)
    }
    
    @Test
    func testDictionaryRemoveValue() {
        let initial = [
            "foo": 1,
            "bar": 2,
        ]
        let sync = Synchronized(initial: initial)
        
        sync.removeValue(forKey: "foo")
        
        #expect(sync["foo"] == nil)
        #expect(sync["bar"] == 2)
    }

//MARK: - Collection Operations
    
    @Test
    func testCollectionSubscriptGet() {
        let initial: [Int] = [1, 2, 3]
        let sync = Synchronized(initial: initial)
        
        #expect(sync.count == 3)
        #expect(sync[0] == 1)
        #expect(sync[1] == 2)
        #expect(sync[2] == 3)
    }
    
    @Test
    func testMutableCollectionSubscriptSet() {
        let initial: [Int] = [1, 2, 3]
        let sync = Synchronized(initial: initial)

        #expect(sync.count == 3)

        sync[1] = 42

        #expect(sync.count == 3)
        #expect(sync[0] == 1)
        #expect(sync[1] == 42)
        #expect(sync[2] == 3)
    }
    
    @Test
    func testRangeReplaceableCollectionAppendElement() {
        let initial: [Int] = [1, 2, 3]
        let sync = Synchronized(initial: initial)

        #expect(sync.count == 3)

        sync.append(4)

        #expect(sync.count == 4)
        #expect(sync[0] == 1)
        #expect(sync[1] == 2)
        #expect(sync[2] == 3)
        #expect(sync[3] == 4)
    }

    @Test
    func testRangeReplaceableCollectionAppendSequence() {
        let initial: [Int] = [1, 2, 3]
        let sync = Synchronized(initial: initial)

        #expect(sync.count == 3)

        sync.append(contentsOf: [4, 5, 6])

        #expect(sync.count == 6)
        #expect(sync[0] == 1)
        #expect(sync[1] == 2)
        #expect(sync[2] == 3)
        #expect(sync[3] == 4)
        #expect(sync[4] == 5)
        #expect(sync[5] == 6)
    }

    @Test
    func testRangeReplaceableCollectionInsertElement() {
        let initial: [Int] = [1, 2, 3]
        let sync = Synchronized(initial: initial)

        #expect(sync.count == 3)

        sync.insert(4, at: 1)

        #expect(sync.count == 4)
        #expect(sync[0] == 1)
        #expect(sync[1] == 4)
        #expect(sync[2] == 2)
        #expect(sync[3] == 3)
    }

    @Test
    func testRangeReplaceableCollectionInsertSequence() {
        let initial: [Int] = [1, 2, 3]
        let sync = Synchronized(initial: initial)

        #expect(sync.count == 3)

        sync.insert(contentsOf: [4, 5, 6], at: 1)

        #expect(sync.count == 6)
        #expect(sync[0] == 1)
        #expect(sync[1] == 4)
        #expect(sync[2] == 5)
        #expect(sync[3] == 6)
        #expect(sync[4] == 2)
        #expect(sync[5] == 3)
    }

    @Test
    func testRangeReplaceableCollectionRemoveAll() {
        let initial: [Int] = [1, 2, 3]
        let sync = Synchronized(initial: initial)

        #expect(sync.count == 3)

        sync.removeAll()

        #expect(sync.count == 0)
    }

}
