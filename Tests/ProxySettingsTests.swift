import Foundation

@main
struct ProxySettingsTests {
    static func main() throws {
        let proxy = try require(ProxyEndpoint(host: " proxy.example ", port: 3128))
        precondition(proxy.authority == "proxy.example:3128")
        precondition(ProxyEndpoint(host: "[::1]", port: 8080)?.authority == "[::1]:8080")
        precondition(ProxyEndpoint(host: "https://proxy.example", port: 3128) == nil)
        precondition(ProxyEndpoint(host: "proxy.example", port: 65536) == nil)

        let original: [String: Any] = ["HTTPEnable": 1, "HTTPProxy": "old.example", "HTTPPort": 8888,
                                       "ProxyAutoConfigEnable": 1, "ExceptionsList": ["*.example"]]
        let before = ProxySettings(original)
        let after = before.updating(with: ProxySelection(http: nil, https: proxy))
        let changed = after.merged(into: original)

        precondition(changed["HTTPEnable"] as? Int == 0)
        precondition(changed["HTTPProxy"] as? String == "old.example")
        precondition(changed["HTTPSEnable"] as? Int == 1)
        precondition(changed["HTTPSProxy"] as? String == "proxy.example")
        precondition(changed["HTTPSPort"] as? Int == 3128)
        precondition(changed["ProxyAutoConfigEnable"] as? Int == 1)
        precondition(changed["ExceptionsList"] as? [String] == ["*.example"])

        let reloaded = try PropertyListDecoder().decode(ProxySettings.self, from: PropertyListEncoder().encode(before))
        let restored = reloaded.merged(into: changed)
        precondition(NSDictionary(dictionary: restored).isEqual(to: original))
        print("Proxy settings tests passed.")
    }

    private static func require<T>(_ value: T?) throws -> T {
        guard let value else { throw ProxyError.message("Expected a valid proxy endpoint.") }
        return value
    }
}
