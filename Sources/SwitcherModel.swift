import Foundation
import SwiftUI

@MainActor
final class SwitcherModel: ObservableObject {
    @Published private(set) var services: [NetworkService] = []
    @Published private(set) var serviceID: String?
    @Published private(set) var profiles: [ProxyProfile] = []
    @Published private(set) var busy = false
    @Published private(set) var notice: String?
    @Published private(set) var hasError = false
    @Published var http = ProxyDraft()
    @Published var https = ProxyDraft()
    @Published var useSameAddress = false
    @Published var profileName = ""

    private let defaults = UserDefaults.standard
    private let profilesKey = "profiles"

    init() {
        if let data = defaults.data(forKey: profilesKey),
           let saved = try? PropertyListDecoder().decode([ProxyProfile].self, from: data) {
            profiles = saved
        }
        refresh()
    }

    var service: NetworkService? {
        services.first { $0.id == serviceID }
    }

    var hasEnabledProxy: Bool {
        guard let settings = service?.settings else { return false }
        return settings.http.isEnabled || settings.https.isEnabled
    }

    var canRestore: Bool {
        serviceID.map(SystemProxy.canRestore(serviceID:)) ?? false
    }

    func refresh() {
        do {
            services = try SystemProxy.services()
            let id = service?.id ?? services.first(where: { $0.enabled })?.id ?? services.first?.id
            selectService(id)
            if services.isEmpty { report("No network services with proxy settings were found.") }
        } catch {
            services = []
            selectService(nil)
            report(error.localizedDescription, error: true)
        }
    }

    func selectService(_ id: String?) {
        serviceID = id
        if let settings = service?.settings {
            http = ProxyDraft(settings.http)
            https = ProxyDraft(settings.https)
        } else {
            http = ProxyDraft()
            https = ProxyDraft()
        }
        useSameAddress = false
        notice = nil
    }

    func applyDraft() {
        do {
            apply(try draftSelection())
        } catch {
            report(error.localizedDescription, error: true)
        }
    }

    func applyProfile(_ profile: ProxyProfile) {
        apply(profile.selection)
    }

    func restore() {
        guard let service else { return }
        changeSettings(success: "Restored the previous settings for \(service.name).") {
            try SystemProxy.restore(serviceID: service.id)
        }
    }

    func testConnection() {
        do {
            let selection = try draftSelection()
            guard selection.http != nil || selection.https != nil else {
                report("Turn on HTTP or HTTPS to test an endpoint.", error: true)
                return
            }
            busy = true
            report("Testing proxy endpoints…")
            Task {
                let result = await Task.detached(priority: .userInitiated) { ProxyProbe.run(selection) }.value
                busy = false
                report(result)
            }
        } catch {
            report(error.localizedDescription, error: true)
        }
    }

    func saveProfile() {
        let name = profileName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        do {
            let selection = try draftSelection()
            guard !profiles.contains(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) else {
                report("A profile already uses that name.", error: true)
                return
            }
            let profile = ProxyProfile(name: name, selection: selection)
            try persistProfiles(profiles + [profile])
            profileName = ""
            report("Saved “\(name)”.")
        } catch {
            report(error.localizedDescription, error: true)
        }
    }

    func removeProfile(_ profile: ProxyProfile) {
        do {
            try persistProfiles(profiles.filter { $0.id != profile.id })
            report("Deleted “\(profile.name)”.")
        } catch {
            report(error.localizedDescription, error: true)
        }
    }

    private func draftSelection() throws -> ProxySelection {
        var secure = https
        if useSameAddress && http.enabled {
            secure.host = http.host
            secure.port = http.port
        }
        return ProxySelection(http: try http.endpoint(for: .http), https: try secure.endpoint(for: .https))
    }

    private func apply(_ selection: ProxySelection) {
        guard let service else { return }
        let expected = service.settings
        let next = expected.updating(with: selection)
        changeSettings(success: "Applied proxy settings to \(service.name).") {
            try SystemProxy.apply(selection, to: service.id, expected: expected)
            let actual = try SystemProxy.services().first(where: { $0.id == service.id })?.settings
            guard actual == next else {
                throw ProxyError.message("Could not verify the saved settings for \(service.name).")
            }
        }
    }

    private func changeSettings(success: String, _ operation: @escaping @Sendable () throws -> Void) {
        guard !busy else { return }
        busy = true
        report("Waiting for macOS…")
        Task {
            let outcome = await Task.detached(priority: .userInitiated) { Result { try operation() } }.value
            refresh()
            busy = false
            switch outcome {
            case .success:
                if !hasError || notice == nil { report(success) }
            case .failure(let error):
                report(error.localizedDescription, error: true)
            }
        }
    }

    private func persistProfiles(_ updated: [ProxyProfile]) throws {
        defaults.set(try PropertyListEncoder().encode(updated), forKey: profilesKey)
        profiles = updated
    }

    private func report(_ message: String, error: Bool = false) {
        notice = message
        hasError = error
    }
}
