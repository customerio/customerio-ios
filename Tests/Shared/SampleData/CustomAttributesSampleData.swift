import Foundation

public enum CustomAttributesSampleData {
    // Common set of custom attributes that tries to demonstrate all of the different ways the customers might use
    // attributes to verify we support it all.
    public static let givenCustomAttributes: [String: Any] = [
        "firstName": "Dana",
        "last_name": "Green",
        "HOBBY": "football",
        "nested": [
            "is adult": true,
            "age": 20
        ]
    ]
    public static let expectedCustomAttributesString = """
    "firstName":"Dana","HOBBY":"football","last_name":"Green","nested":{"age":20,"is adult":true}
    """.trimmingCharacters(in: .whitespacesAndNewlines)
}
