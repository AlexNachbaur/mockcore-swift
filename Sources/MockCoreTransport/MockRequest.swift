import Foundation

/// The protocol-neutral view of an incoming HTTP request that a ``MockHost`` hands to its
/// registered ``MockService``s.
///
/// The host does no body parsing: `body` is the raw bytes, and each service decodes it however
/// its protocol expects (GraphQL as a JSON operation envelope, REST against its spec, …).
public struct MockRequest: Sendable {
    /// The HTTP method, uppercased (`"GET"`, `"POST"`, …).
    public let method: String
    /// The request URI exactly as sent, including any query string.
    public let uri: String
    /// The path component of the URI, without the query string.
    public let path: String
    /// All request headers, in wire order. Use ``header(_:)`` for case-insensitive lookup.
    public let headers: [(name: String, value: String)]
    /// The raw request body, empty when the request had none.
    public let body: Data

    /// Creates a request.
    public init(method: String, uri: String, headers: [(name: String, value: String)] = [], body: Data = Data()) {
        self.method = method.uppercased()
        self.uri = uri
        self.path = uri.split(separator: "?", maxSplits: 1).first.map(String.init) ?? uri
        self.headers = headers
        self.body = body
    }

    /// The first value of the named header, matched case-insensitively.
    public func header(_ name: String) -> String? {
        headers.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }?.value
    }

    /// The decoded query parameters, in wire order. Parameters without a value decode as `""`.
    public var queryItems: [(name: String, value: String)] {
        guard let components = URLComponents(string: uri), let items = components.queryItems else {
            return []
        }
        return items.map { ($0.name, $0.value ?? "") }
    }

    /// The first value of the named query parameter, or `nil`.
    public func queryValue(_ name: String) -> String? {
        queryItems.first { $0.name == name }?.value
    }
}
