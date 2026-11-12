import Darwin
import Foundation

enum WebProtocol: String, CaseIterable {
    case http = "HTTP"
    case https = "HTTPS"

    var testURL: String { "\(rawValue.lowercased())://example.com/" }
}

struct ProxyEndpoint: Codable, Equatable {
    let host: String
    let port: Int

    init?(host: String, port: Int) {
        let address = host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (1...65535).contains(port) else { return nil }

        if address.contains(":") {
            let literal = address.hasPrefix("[") && address.hasSuffix("]")
                ? String(address.dropFirst().dropLast()) : address
            var binary = in6_addr()
            guard inet_pton(AF_INET6, literal, &binary) == 1 else { return nil }
            self.host = literal
        } else {
            let hostname = address.hasSuffix(".") ? String(address.dropLast()) : address
            let labels = hostname.split(separator: ".", omittingEmptySubsequences: false)
            let labelPattern = #"\A[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?\z"#
            guard !labels.isEmpty, hostname.utf8.count <= 253,
                  labels.allSatisfy({ $0.range(of: labelPattern, options: .regularExpression) != nil })
            else { return nil }
            self.host = address
        }
        self.port = port
    }

    var authority: String {
        host.contains(":") ? "[\(host)]:\(port)" : "\(host):\(port)"
    }
}

struct ProxyValues: Codable, Equatable {
    var enabled: Int?
    var host: String?
    var port: Int?

    var isEnabled: Bool { (enabled ?? 0) != 0 }

    init(_ configuration: [String: Any], for scheme: WebProtocol) {
        enabled = configuration[scheme.rawValue + "Enable"] as? Int
        host = configuration[scheme.rawValue + "Proxy"] as? String
        port = configuration[scheme.rawValue + "Port"] as? Int
    }

    func updating(with endpoint: ProxyEndpoint?) -> Self {
        var updated = self
        updated.enabled = endpoint == nil ? 0 : 1
        if let endpoint {
            updated.host = endpoint.host
            updated.port = endpoint.port
        }
        return updated
    }

    func write(to configuration: inout [String: Any], for scheme: WebProtocol) {
        configuration[scheme.rawValue + "Enable"] = enabled
        configuration[scheme.rawValue + "Proxy"] = host
        configuration[scheme.rawValue + "Port"] = port
    }
}

struct ProxySettings: Codable, Equatable {
    var http: ProxyValues
    var https: ProxyValues

    init(_ configuration: [String: Any]) {
        http = ProxyValues(configuration, for: .http)
        https = ProxyValues(configuration, for: .https)
    }

    func updating(with selection: ProxySelection) -> Self {
        var updated = self
        updated.http = http.updating(with: selection.http)
        updated.https = https.updating(with: selection.https)
        return updated
    }

    func merged(into configuration: [String: Any]) -> [String: Any] {
        var updated = configuration
        http.write(to: &updated, for: .http)
        https.write(to: &updated, for: .https)
        return updated
    }
}

struct ProxySelection: Codable, Equatable {
    var http: ProxyEndpoint?
    var https: ProxyEndpoint?
}

struct ProxyDraft {
    var enabled = false
    var host = ""
    var port = ""

    init() {}

    init(_ values: ProxyValues) {
        enabled = values.isEnabled
        host = values.host ?? ""
        port = values.port.map(String.init) ?? ""
    }

    func endpoint(for scheme: WebProtocol) throws -> ProxyEndpoint? {
        guard enabled else { return nil }
        let portText = port.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let port = Int(portText), let endpoint = ProxyEndpoint(host: host, port: port) else {
            throw ProxyError.message("\(scheme.rawValue) needs a hostname or IP address and a port from 1 to 65535.")
        }
        return endpoint
    }
}

struct ProxyProfile: Identifiable, Codable {
    var id = UUID()
    let name: String
    let selection: ProxySelection
}

enum ProxyError: LocalizedError {
    case message(String)

    var errorDescription: String? {
        switch self {
        case .message(let message): return message
        }
    }
}
