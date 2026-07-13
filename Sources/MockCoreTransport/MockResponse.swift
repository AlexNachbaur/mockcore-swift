import Foundation
import MockCore

/// The response a ``MockService`` returns for a claimed request.
///
/// The host writes `status`, the headers (adding `Content-Length` and connection management),
/// and the body verbatim.
public struct MockResponse: Sendable {
    /// The HTTP status code.
    public var status: Int
    /// Response headers, written in order. `Content-Length` is added by the host.
    public var headers: [(name: String, value: String)]
    /// The raw response body.
    public var body: Data

    /// Creates a response.
    public init(status: Int = 200, headers: [(name: String, value: String)] = [], body: Data = Data()) {
        self.status = status
        self.headers = headers
        self.body = body
    }

    /// A JSON response from pre-serialized data.
    public static func json(_ data: Data, status: Int = 200) -> MockResponse {
        MockResponse(status: status, headers: [("Content-Type", "application/json")], body: data)
    }

    /// A JSON response from a value tree. Object keys are sorted for deterministic output.
    public static func json(_ value: MockValue, status: Int = 200) throws -> MockResponse {
        .json(try value.jsonData(), status: status)
    }

    /// A plain-text response.
    public static func text(_ text: String, status: Int = 200) -> MockResponse {
        MockResponse(status: status, headers: [("Content-Type", "text/plain")], body: Data(text.utf8))
    }
}
