// Copies of Services deliveries/backgroundpush/testdata outputs: what the push relay sends to APNs and to FCM.
// Package.swift has no test resource declaration; keep these literals in sync with that testdata by hand.
import Foundation

enum BackgroundPushFixtures {
    static let apns = #"""
    {
      "CIO-Background-Delivery-ID": "fixture-delivery-1",
      "CIO-Background-Delivery-Token": "fixture-apns-token-1",
      "aps": {
        "content-available": 1
      },
      "cıo-x": "dotless",
      "note": "line one\nsays \"hi\" \u003cb\u003e\u0026\u003c/b\u003e ✓",
      "order_id": "A-1001",
      "title": "Order shipped"
    }

    """#
    static let fcm = #"""
    {
      "message": {
        "apns": {
          "headers": {
            "apns-priority": "5",
            "apns-push-type": "background"
          },
          "payload": {
            "aps": {
              "content-available": 1
            },
            "cıo-x": "dotless",
            "note": "line one\nsays \"hi\" \u003cb\u003e\u0026\u003c/b\u003e ✓",
            "order_id": "A-1001",
            "title": "Order shipped"
          }
        },
        "data": {
          "CIO-Background-Delivery-ID": "fixture-delivery-1",
          "CIO-Background-Delivery-Token": "fixture-fcm-token-1"
        }
      }
    }

    """#
}
