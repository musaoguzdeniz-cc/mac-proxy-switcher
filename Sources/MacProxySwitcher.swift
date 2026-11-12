import AppKit
import SwiftUI

@main
@MainActor
struct MacProxySwitcher: App {
    @StateObject private var model = SwitcherModel()

    var body: some Scene {
        MenuBarExtra {
            ProxyPanel(model: model)
        } label: {
            Label("Mac Proxy Switcher", systemImage: model.hasEnabledProxy ? "network.badge.shield.half.filled" : "network")
        }
        .menuBarExtraStyle(.window)
    }
}

private struct ProxyPanel: View {
    @ObservedObject var model: SwitcherModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Mac Proxy Switcher").font(.headline)
                Spacer()
                if model.busy { ProgressView().controlSize(.small) }
                Button(action: model.refresh) {
                    Label("Refresh settings", systemImage: "arrow.clockwise")
                        .labelStyle(.iconOnly)
                }
                .disabled(model.busy)
                .help("Read settings again from macOS")
            }

            VStack(alignment: .leading, spacing: 12) {
                servicePicker
                if let service = model.service {
                    status(for: service)
                    Divider()
                    endpointEditor(.http, draft: $model.http, shareAddress: false)
                    endpointEditor(.https, draft: $model.https,
                                   shareAddress: model.useSameAddress && model.http.enabled)
                    if model.http.enabled && model.https.enabled {
                        Toggle("Use the HTTP address for HTTPS", isOn: $model.useSameAddress)
                    }
                    HStack {
                        Button("Apply", action: model.applyDraft)
                            .buttonStyle(.borderedProminent)
                        Button("Test connection", action: model.testConnection)
                            .disabled(!model.http.enabled && !model.https.enabled)
                            .help("Send a request to example.com through each enabled endpoint in this form")
                        Spacer()
                        Button("Restore previous", action: model.restore)
                            .disabled(!model.canRestore)
                    }
                    Divider()
                    profileControls
                }
            }
            .disabled(model.busy)

            if let notice = model.notice {
                Text(notice)
                    .font(.callout)
                    .foregroundStyle(model.hasError ? Color.red : Color.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Spacer()
                Button("Quit", role: .cancel) { NSApplication.shared.terminate(nil) }
                    .disabled(model.busy)
            }
        }
        .padding(16)
        .frame(width: 405)
    }

    private var servicePicker: some View {
        Picker("Network service", selection: Binding(
            get: { model.serviceID },
            set: { model.selectService($0) }
        )) {
            if model.services.isEmpty { Text("Unavailable").tag(nil as String?) }
            ForEach(model.services) { service in
                Text(service.enabled ? service.name : "\(service.name) (disabled)").tag(Optional(service.id))
            }
        }
    }

    private func status(for service: NetworkService) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Saved in macOS")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("HTTP  \(summary(service.settings.http))")
            Text("HTTPS  \(summary(service.settings.https))")
            if service.automaticProxy {
                Label("Automatic proxy configuration is active for this service.",
                      systemImage: "info.circle")
                    .foregroundStyle(.secondary)
            }
        }
        .font(.callout)
        .textSelection(.enabled)
    }

    private func summary(_ values: ProxyValues) -> String {
        guard values.isEnabled else { return "Off" }
        guard let host = values.host, let port = values.port else { return "On" }
        return ProxyEndpoint(host: host, port: port)?.authority ?? "\(host):\(port)"
    }

    private func endpointEditor(_ scheme: WebProtocol, draft: Binding<ProxyDraft>, shareAddress: Bool) -> some View {
        HStack(spacing: 8) {
            Toggle(scheme.rawValue, isOn: draft.enabled)
                .frame(width: 82, alignment: .leading)
            TextField("Hostname or IP address", text: shareAddress ? .constant(model.http.host) : draft.host)
                .accessibilityLabel("\(scheme.rawValue) proxy hostname or IP address")
                .disabled(!draft.wrappedValue.enabled || shareAddress)
            TextField("Port", text: shareAddress ? .constant(model.http.port) : draft.port)
                .accessibilityLabel("\(scheme.rawValue) proxy port")
                .frame(width: 58)
                .disabled(!draft.wrappedValue.enabled || shareAddress)
        }
    }

    private var profileControls: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                TextField("New profile name", text: $model.profileName)
                    .accessibilityLabel("New profile name")
                Button("Save profile", action: model.saveProfile)
                    .disabled(model.profileName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            if !model.profiles.isEmpty {
                HStack {
                    Menu("Apply profile") {
                        ForEach(model.profiles) { profile in
                            Button(profile.name) { model.applyProfile(profile) }
                        }
                    }
                    Menu("Delete profile") {
                        ForEach(model.profiles) { profile in
                            Button(profile.name, role: .destructive) { model.removeProfile(profile) }
                        }
                    }
                }
            }
        }
    }
}
