import Foundation

enum ProxyProbe {
    static func run(_ selection: ProxySelection) -> String {
        let tests: [(WebProtocol, ProxyEndpoint?)] = [(.http, selection.http), (.https, selection.https)]
        return tests.compactMap { scheme, endpoint in
            endpoint.map { "\(scheme.rawValue) · \(test(scheme, via: $0))" }
        }.joined(separator: "\n")
    }

    private static func test(_ scheme: WebProtocol, via endpoint: ProxyEndpoint) -> String {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/curl")
        task.arguments = [
            "--disable", "--silent", "--connect-timeout", "4", "--max-time", "8",
            "--proxy", "http://\(endpoint.authority)", "--noproxy", "", "--output", "/dev/null",
            "--write-out", "%{http_code} %{http_connect}", scheme.testURL,
        ]
        // Ignore inherited proxy and TLS overrides while testing this endpoint.
        task.environment = ["LC_ALL": "C"]
        let output = Pipe()
        task.standardOutput = output
        task.standardError = FileHandle.nullDevice

        do {
            try task.run()
        } catch {
            return "Could not launch curl."
        }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()
        let codes = String(decoding: data, as: UTF8.self).split(separator: " ").compactMap { Int($0) }
        let response = codes.first ?? 0
        let tunnel = codes.last ?? 0
        if response == 407 || tunnel == 407 { return "Proxy requires authentication (407)." }
        guard task.terminationStatus == 0 else {
            return "Request failed (curl \(task.terminationStatus))."
        }
        guard (200..<400).contains(response) else { return "Test endpoint returned \(response)." }
        return "Received HTTP \(response) through the proxy."
    }
}
