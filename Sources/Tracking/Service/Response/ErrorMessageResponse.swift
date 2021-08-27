import Foundation

/**
 The API returns error response bodies in the format:
 ```
 {"meta": { "error": "invalid id" }}
 ```
 */
public class ErrorMessageResponse: Codable {
    let meta: Meta

    public class Meta: Codable {
        let error: String
    }
}
