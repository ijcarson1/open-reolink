import SwiftUI
import ReolinkClient
import Storage

@MainActor
public final class AddCameraFormModel: ObservableObject {
    @Published public var displayName: String = ""
    @Published public var lanIP: String = ""
    @Published public var kind: CameraKind = .camera
    @Published public var adminUsername: String = "admin"
    @Published public var adminPassword: String = ""
    @Published public var eventsUsername: String = "onvif"
    @Published public var eventsPassword: String = ""
    public var discoveredVia: CameraDiscoverySource = .manual
    public var discoveredModel: String? = nil

    @Published public private(set) var isVerifying: Bool = false
    @Published public private(set) var errorMessage: String?

    public init() {}

    public func prefill(from discovered: DiscoveredCamera) {
        lanIP = discovered.ip
        if displayName.isEmpty { displayName = discovered.model ?? discovered.ip }
        discoveredModel = discovered.model
        discoveredVia = .onvifDiscovery
    }

    public var canSubmit: Bool {
        !displayName.isEmpty
            && IPv4.isValid(lanIP)
            && !adminUsername.isEmpty
            && !adminPassword.isEmpty
            && !eventsUsername.isEmpty
            && !eventsPassword.isEmpty
    }

    public func submit(via service: CameraService) async -> Bool {
        guard canSubmit else { return false }
        errorMessage = nil
        isVerifying = true
        defer { isVerifying = false }

        let camera = Camera(
            displayName: displayName.trimmingCharacters(in: .whitespaces),
            lanIP: lanIP,
            kind: kind,
            model: discoveredModel,
            adminUsername: adminUsername,
            eventsUsername: eventsUsername,
            discoveredVia: discoveredVia
        )

        // Verify admin creds against the camera before persisting (per ADR-0005's
        // "two passwords, role-keyed" model).
        let cgi = ReolinkCGIClient(camera: camera, password: adminPassword)
        do {
            _ = try await cgi.fetchSnapshot()
        } catch let error as CameraClientError {
            errorMessage = describe(error)
            return false
        } catch {
            errorMessage = error.localizedDescription
            return false
        }

        // Verify events creds via ONVIF GetDeviceInformation (Slice 5).
        let onvif = ReolinkONVIFClient(camera: camera, eventsPassword: eventsPassword)
        do {
            _ = try await onvif.verifyCredentials()
        } catch ONVIFError.notAuthorized {
            errorMessage = "Events credentials rejected — make sure you've created the second (non-admin) User-level account on the camera; see the setup guide."
            return false
        } catch {
            // ONVIF reachability problems shouldn't block save — log and continue;
            // Slice 5's EventCoordinator will retry once the camera is reachable.
        }

        do {
            try service.add(camera: camera, adminPassword: adminPassword, eventsPassword: eventsPassword)
            return true
        } catch {
            errorMessage = "Could not save camera: \(error.localizedDescription)"
            return false
        }
    }

    private func describe(_ error: CameraClientError) -> String {
        switch error {
        case .unauthorized: return "Authentication failed — check the admin username and password."
        case .lockedOut: return "The camera is locked out by repeated failed logins. Wait ~5 minutes and try again."
        case .unreachable(let detail): return "Could not reach the camera at \(lanIP): \(detail)"
        case .unexpectedResponse(let status): return "Camera returned an unexpected HTTP \(status)."
        case .decoding(let detail): return "Unexpected response from camera: \(detail)"
        }
    }
}

public struct AddCameraForm: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @StateObject private var model = AddCameraFormModel()

    public init() {}

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Add a Reolink camera")
                .font(.system(size: 14, weight: .semibold))
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 8)

            Form {
                Section("Camera") {
                    TextField("Display name", text: $model.displayName)
                    TextField("LAN IP (e.g. 192.168.1.20)", text: $model.lanIP)
                    Picker("Kind", selection: $model.kind) {
                        Text("Camera").tag(CameraKind.camera)
                        Text("Doorbell").tag(CameraKind.doorbell)
                    }
                }

                Section("Admin credentials (CGI: snapshot, settings)") {
                    TextField("Admin username", text: $model.adminUsername)
                    SecureField("Admin password", text: $model.adminPassword)
                }

                Section("Events credentials (ONVIF events — verified in Slice 5)") {
                    TextField("Events username", text: $model.eventsUsername)
                    SecureField("Events password", text: $model.eventsPassword)
                }

                if let error = model.errorMessage {
                    Text(error)
                        .font(.system(size: 11))
                        .foregroundStyle(.red)
                }
            }
            .formStyle(.grouped)

            Divider()
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button {
                    Task {
                        let ok = await model.submit(via: appState.service)
                        if ok {
                            appState.reload()
                            dismiss()
                        }
                    }
                } label: {
                    if model.isVerifying {
                        ProgressView().controlSize(.small)
                    } else {
                        Text("Save")
                    }
                }
                .keyboardShortcut(.return)
                .disabled(!model.canSubmit || model.isVerifying)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .frame(minWidth: 420, idealHeight: 560)
    }
}
