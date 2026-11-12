import Foundation
import Security
import SystemConfiguration

struct NetworkService: Identifiable {
    let id: String
    let name: String
    let enabled: Bool
    let settings: ProxySettings
    let automaticProxy: Bool
}

private struct UndoEntry: Codable {
    let before: ProxySettings
    let after: ProxySettings
}

enum SystemProxy {
    static func services() throws -> [NetworkService] {
        guard let preferences = SCPreferencesCreate(nil, "Mac Proxy Switcher" as CFString, nil) else {
            throw systemError("Read network preferences")
        }
        return try networkServices(in: preferences).compactMap { service in
            guard let id = SCNetworkServiceGetServiceID(service),
                  let name = SCNetworkServiceGetName(service),
                  let proxies = SCNetworkServiceCopyProtocol(service, kSCNetworkProtocolTypeProxies)
            else { return nil }

            let config = configuration(of: proxies)
            let automatic = ["ProxyAutoConfigEnable", "ProxyAutoDiscoveryEnable"].contains {
                (config[$0] as? Int ?? 0) != 0
            }
            return NetworkService(id: id as String, name: name as String,
                                  enabled: SCNetworkServiceGetEnabled(service),
                                  settings: ProxySettings(config), automaticProxy: automatic)
        }
    }

    static func canRestore(serviceID: String) -> Bool {
        undoEntry(for: serviceID) != nil
    }

    static func apply(_ selection: ProxySelection, to serviceID: String, expected: ProxySettings) throws {
        try update(serviceID: serviceID) { preferences, proxies, config in
            let current = ProxySettings(config)
            guard current == expected else {
                throw ProxyError.message("The service settings changed. Review the refreshed values and try again.")
            }
            let next = current.updating(with: selection)
            if next != current {
                // Save both states before committing so a restart can recover the previous values.
                let oldEntry = undoEntry(for: serviceID)
                saveUndo(UndoEntry(before: current, after: next), for: serviceID)
                do {
                    try commit(next, merging: config, into: proxies, with: preferences)
                } catch {
                    saveUndo(oldEntry, for: serviceID)
                    throw error
                }
            }
            try activate(preferences)
        }
    }

    static func restore(serviceID: String) throws {
        try update(serviceID: serviceID) { preferences, proxies, config in
            guard let entry = undoEntry(for: serviceID) else {
                throw ProxyError.message("There are no saved settings to restore for this service.")
            }
            let current = ProxySettings(config)
            if current == entry.after {
                try commit(entry.before, merging: config, into: proxies, with: preferences)
            } else if current != entry.before {
                throw ProxyError.message("The HTTP or HTTPS settings changed after the last update. Restore them manually to avoid overwriting those changes.")
            }
            try activate(preferences)
            saveUndo(nil, for: serviceID)
        }
    }

    private static func networkServices(in preferences: SCPreferences) throws -> [SCNetworkService] {
        guard let location = SCNetworkSetCopyCurrent(preferences),
              let services = SCNetworkSetCopyServices(location) as? [SCNetworkService] else {
            throw systemError("Read the current network location")
        }
        return services
    }

    private static func update(
        serviceID: String,
        _ edit: (SCPreferences, SCNetworkProtocol, [String: Any]) throws -> Void
    ) throws {
        var authorization: AuthorizationRef?
        let status = AuthorizationCreate(nil, nil, [], &authorization)
        guard status == errAuthorizationSuccess, let authorization else {
            throw ProxyError.message("Could not start macOS authorization (\(status)).")
        }
        defer { AuthorizationFree(authorization, []) }

        guard let preferences = SCPreferencesCreateWithAuthorization(
            nil, "Mac Proxy Switcher" as CFString, nil, authorization
        ) else { throw systemError("Open authorized network preferences") }

        guard SCPreferencesLock(preferences, false) else { throw systemError("Lock network preferences") }
        defer { SCPreferencesUnlock(preferences) }

        let services = try networkServices(in: preferences)
        guard let service = services.first(where: { SCNetworkServiceGetServiceID($0) as String? == serviceID }),
              let proxies = SCNetworkServiceCopyProtocol(service, kSCNetworkProtocolTypeProxies)
        else { throw ProxyError.message("This network service is no longer available in the current location.") }

        try edit(preferences, proxies, configuration(of: proxies))
    }

    private static func configuration(of proxies: SCNetworkProtocol) -> [String: Any] {
        SCNetworkProtocolGetConfiguration(proxies) as? [String: Any] ?? [:]
    }

    private static func commit(
        _ settings: ProxySettings,
        merging config: [String: Any],
        into proxies: SCNetworkProtocol,
        with preferences: SCPreferences
    ) throws {
        guard SCNetworkProtocolSetConfiguration(proxies, settings.merged(into: config) as CFDictionary)
        else { throw systemError("Update the service’s proxy settings") }
        guard SCPreferencesCommitChanges(preferences) else { throw systemError("Save proxy settings") }
    }

    private static func activate(_ preferences: SCPreferences) throws {
        guard SCPreferencesApplyChanges(preferences) else {
            throw systemError("Apply saved settings. The saved values are shown after refresh.")
        }
    }

    private static func undoEntry(for serviceID: String) -> UndoEntry? {
        guard let data = UserDefaults.standard.data(forKey: "undo.\(serviceID)") else { return nil }
        return try? PropertyListDecoder().decode(UndoEntry.self, from: data)
    }

    private static func saveUndo(_ entry: UndoEntry?, for serviceID: String) {
        let key = "undo.\(serviceID)"
        if let entry, let data = try? PropertyListEncoder().encode(entry) {
            UserDefaults.standard.set(data, forKey: key)
        } else {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }

    private static func systemError(_ action: String) -> ProxyError {
        let status = SCError()
        if status == kSCStatusAccessError {
            return .message("\(action). macOS denied access or authorization was canceled.")
        }
        return .message("\(action). \(String(cString: SCErrorString(status))) (\(status))")
    }
}
