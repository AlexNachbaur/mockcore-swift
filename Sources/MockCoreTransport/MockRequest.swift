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
        self.path = String(uri.prefix(while: { $0 != "?" }))
        self.headers = headers
        self.body = body
    }

    /// The first value of the named header, matched case-insensitively.
    public func header(_ name: String) -> String? {
        headers.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }?.value
    }

    /// The decoded query parameters, in wire order. Parameters without a value decode as `""`.
    ///
    /// Each name and value is percent-decoded independently (an undecodable component is passed
    /// through raw), so one malformed parameter never disables decoding for the others — unlike
    /// whole-URI parsers, whose strictness also varies across Foundation versions.
    public var queryItems: [(name: String, value: String)] {
        guard let queryStart = uri.firstIndex(of: "?") else { return [] }
        let query = uri[uri.index(after: queryStart)...]
        return query.split(separator: "&").map { pair in
            let parts = pair.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            let rawName = String(parts.first ?? "")
            let rawValue = parts.count > 1 ? String(parts[1]) : ""
            return (rawName.removingPercentEncoding ?? rawName, rawValue.removingPercentEncoding ?? rawValue)
        }
    }

    /// The first value of the named query parameter, or `nil`.
    public func queryValue(_ name: String) -> String? {
        queryItems.first { $0.name == name }?.value
    }
}
