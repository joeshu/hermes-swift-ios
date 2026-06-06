import SwiftUI
import AVFoundation
import Foundation
import UIKit
import UserNotifications

public struct SettingsView: View {
    @EnvironmentObject var settings: AppSettings
    @ObservedObject var store: EndpointStore
    @State private var editingEndpoint: HermesEndpoint?
    @State private var manualHost: String = ""
    @State private var manualError: String?
    @State private var notificationsError: String?
    @State private var manualWorking = false
    @State private var showingScanner = false
    @State private var preflightStatus: String?
    private let connectionOnly: Bool
    private let onConnected: (() -> Void)?
    @Environment(\.openURL) private var openURL

    @MainActor
    public init(store: EndpointStore = .shared, connectionOnly: Bool = false, onConnected: (() -> Void)? = nil) {
        self.store = store
        self.connectionOnly = connectionOnly
        self.onConnected = onConnected
    }

    public var body: some View {
        NavigationStack {
            Form {
                if connectionOnly {
                    Section {
                        Color.clear
                            .frame(height: 20)
                            .listRowBackground(Color.clear)
                    }
                }

                Section {
                    HStack {
                        Spacer()
                        Button {
                            if let url = URL(string: "https://apps.apple.com/us/app/tailscale/id1470499037") {
                                openURL(url)
                            }
                        } label: {
                            Text("Get Tailscale (App Store)")
                        }
                        .font(.footnote)
                        Spacer()
                    }

                    Text("1) Install Tailscale on your phone and the machine running your webui.\n2) Sign in on both and make sure both are connected.\n3) Scan a QR code or enter the Tailscale IP/hostname for the webui.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    HStack(spacing: 10) {
                        TextField("Tailscale IP[:port]", text: $manualHost)
                            .keyboardType(.URL)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .font(.system(.body, design: .monospaced))

                        Button {
                            startQRScan()
                        } label: {
                            Image(systemName: "qrcode.viewfinder")
                                .font(.title3.weight(.semibold))
                                .frame(width: 30, height: 30)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Scan QR")
                    }

                    HStack {
                        Spacer()
                        Button(manualWorking ? "Checking…" : "Connect") {
                            Task { await saveManualConnection() }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(manualHost.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || manualWorking)
                        Spacer()
                    }

                    Text("If no port is provided, 8787 will be used by default.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    if let preflightStatus {
                        Text(preflightStatus)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }

                    if let manualError {
                        Text(manualError)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }

                    if !store.endpoints.isEmpty {
                        Divider()
                        Text("Saved connections")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)
                        ForEach(store.endpoints) { endpoint in
                            HStack(alignment: .top) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(endpoint.displayName)
                                    Text(endpoint.url.absoluteString)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                        .truncationMode(.middle)

                                    if let health = store.health(for: endpoint) {
                                        HStack(spacing: 6) {
                                            Circle()
                                                .fill(statusColor(for: health.status))
                                                .frame(width: 8, height: 8)
                                            Text(statusText(for: health))
                                                .font(.caption2)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                }
                                Spacer()
                                if store.activeEndpoint?.url == endpoint.url {
                                    Text("Active").font(.caption).foregroundStyle(.green)
                                } else {
                                    Button("Use") {
                                        try? store.setActive(endpoint)
                                        fireConnectSuccessHaptic()
                                        onConnected?()
                                    }
                                    .buttonStyle(.bordered)
                                }
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button("Delete", role: .destructive) {
                                    try? store.remove(endpoint)
                                }
                                Button("Edit") {
                                    editingEndpoint = endpoint
                                }
                                .tint(.blue)
                            }
                            .swipeActions(edge: .leading, allowsFullSwipe: false) {
                                Button("Reconnect") {
                                    try? store.setActive(endpoint)
                                    fireConnectSuccessHaptic()
                                    onConnected?()
                                }
                                .tint(.green)
                            }
                        }
                        .onDelete { idxs in
                            for i in idxs {
                                try? store.remove(store.endpoints[i])
                            }
                        }
                    }
                } header: {
                    if connectionOnly {
                        Text("Connect to WebUI")
                            .font(.title2.weight(.semibold))
                            .frame(maxWidth: .infinity, alignment: .center)
                            .textCase(nil)
                    }
                }

                if !connectionOnly {
                    Section("Notifications") {
                        Toggle("In-app notifications", isOn: $settings.inAppNotificationsEnabled)
                            .onChange(of: settings.inAppNotificationsEnabled) { enabled in
                                guard enabled else {
                                    notificationsError = nil
                                    return
                                }
                                Task { await ensureNotificationPermissionForToggle() }
                            }
                        Button("Open iOS notification settings") {
                            if let url = URL(string: UIApplication.openSettingsURLString) {
                                openURL(url)
                            }
                        }
                        if let notificationsError {
                            Text(notificationsError)
                                .font(.footnote)
                                .foregroundStyle(.red)
                        }
                    }
                }

            }
            .navigationTitle(connectionOnly ? "" : "Connections")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(item: $editingEndpoint) { endpoint in
                EndpointEditorView(store: store, endpoint: endpoint)
            }
            .sheet(isPresented: $showingScanner) {
                QRScannerView(
                    onResult: { value in
                        showingScanner = false
                        Task { await acceptScanned(value) }
                    },
                    onCancel: { showingScanner = false }
                )
            }
        }
    }

    private func acceptScanned(_ raw: String) async {
        manualWorking = true
        manualError = nil
        preflightStatus = nil
        defer { manualWorking = false }
        do {
            let payload = try EndpointQR.decode(raw)
            let endpoint = try EndpointQR.endpoint(from: payload)
            preflightStatus = "Checking connection…"
            _ = try await EndpointPreflight.validate(endpoint.url)
            try store.add(endpoint, activate: true)
            store.markEndpointSuccess(endpoint)
            preflightStatus = nil
            fireConnectSuccessHaptic()
            onConnected?()
        } catch EndpointQR.Error.invalidEncoding {
            manualError = "That doesn't look like a valid connect code."
        } catch EndpointQR.Error.unsupportedVersion(let v) {
            manualError = "Unsupported connect code version (v\(v)). Update the app and webui to compatible versions."
        } catch {
            if let url = EndpointURLBuilder.makeURL(from: manualHost) {
                let endpoint = HermesEndpoint(url: url, displayName: manualHost)
                store.markEndpointFailure(endpoint, message: error.localizedDescription)
            }
            manualError = error.localizedDescription
            preflightStatus = nil
        }
    }

    private func saveManualConnection() async {
        manualWorking = true
        manualError = nil
        preflightStatus = nil
        defer { manualWorking = false }

        let host = manualHost.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !host.isEmpty else {
            manualError = "Enter a webui host."
            return
        }

        guard let url = EndpointURLBuilder.makeURL(from: host) else {
            manualError = "Host must be a valid IP or hostname."
            return
        }

        let endpoint = HermesEndpoint(
            url: url,
            displayName: host
        )

        do {
            preflightStatus = "Checking connection…"
            _ = try await EndpointPreflight.validate(url)
            try store.add(endpoint, activate: true)
            store.markEndpointSuccess(endpoint)
            preflightStatus = nil
            fireConnectSuccessHaptic()
            onConnected?()
        } catch {
            Loggers.app.error("Endpoint preflight failed: \(error.localizedDescription, privacy: .public)")
            store.markEndpointFailure(endpoint, message: error.localizedDescription)
            manualError = error.localizedDescription
            preflightStatus = nil
        }
    }

    private func statusColor(for status: EndpointHealth.Status) -> Color {
        switch status {
        case .success:
            return .green
        case .failure:
            return .red
        case .unknown:
            return .gray
        }
    }

    private func statusText(for health: EndpointHealth) -> String {
        let relative = RelativeDateTimeFormatter().localizedString(for: health.checkedAt, relativeTo: Date())
        switch health.status {
        case .success:
            return "Last check succeeded \(relative)"
        case .failure:
            return "Last check failed \(relative)"
        case .unknown:
            return "Not checked yet"
        }
    }

    private func startQRScan() {
        manualError = nil
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            showingScanner = true
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                DispatchQueue.main.async {
                    if granted {
                        showingScanner = true
                    } else {
                        manualError = "Camera permission was denied."
                    }
                }
            }
        case .denied, .restricted:
            manualError = "Camera permission was denied."
        @unknown default:
            manualError = "Camera permission status is unavailable."
        }
    }

    private func ensureNotificationPermissionForToggle() async {
        notificationsError = nil
        let granted = (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        if !granted {
            settings.inAppNotificationsEnabled = false
            notificationsError = "Notification permission was denied."
        }
    }

    private func fireSuccessHaptic() {
        let gen = UINotificationFeedbackGenerator()
        gen.prepare()
        gen.notificationOccurred(.success)
    }

    private func fireConnectSuccessHaptic() {
        fireSuccessHaptic()
    }
}
