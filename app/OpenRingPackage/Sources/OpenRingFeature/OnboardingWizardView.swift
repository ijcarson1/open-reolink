import SwiftUI
import ReolinkClient

public struct OnboardingWizardView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @StateObject private var model = OnboardingWizardModel()
    @StateObject private var formModel = AddCameraFormModel()

    public init() {}

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            Divider()
            footer
        }
        .frame(minWidth: 460, minHeight: 480)
        .task { await model.start() }
    }

    private var header: some View {
        HStack {
            Text("Add a Reolink camera")
                .font(.system(size: 14, weight: .semibold))
            Spacer()
            Button {
                model.openSetupGuide()
            } label: {
                Image(systemName: "questionmark.circle")
                    .help("Open the setup guide — how to enable ONVIF and create the second user account")
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private var content: some View {
        switch model.step {
        case .searching:
            VStack(spacing: 12) {
                ProgressView()
                Text("Searching for cameras on your network…")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .results(let cameras):
            List(cameras, id: \.id) { camera in
                Button {
                    model.select(camera)
                    formModel.prefill(from: camera)
                } label: {
                    HStack {
                        VStack(alignment: .leading) {
                            Text(camera.model ?? "Reolink camera")
                                .font(.system(size: 12, weight: .medium))
                            Text(camera.ip)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .foregroundStyle(.secondary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        case .noResults:
            VStack(spacing: 8) {
                Text("No cameras found via auto-discovery.")
                    .font(.system(size: 13, weight: .medium))
                Text("This is normal on VLANs or firewalled subnets. Add yours manually below.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onAppear { model.switchToManual() }
        case .credentials, .manual:
            credentialsForm
        }
    }

    private var credentialsForm: some View {
        AddCameraFormBody(model: formModel)
            .padding(.horizontal, 12)
    }

    private var footer: some View {
        HStack {
            switch model.step {
            case .results:
                Button("Don't see your camera?") {
                    model.switchToManual()
                }
                .buttonStyle(.plain)
            default:
                EmptyView()
            }
            Spacer()
            Button("Cancel") { dismiss() }
            switch model.step {
            case .credentials, .manual:
                Button {
                    Task {
                        let ok = await formModel.submit(via: appState.service)
                        if ok {
                            appState.reload()
                            dismiss()
                        }
                    }
                } label: {
                    if formModel.isVerifying {
                        ProgressView().controlSize(.small)
                    } else {
                        Text("Save")
                    }
                }
                .keyboardShortcut(.return)
                .disabled(!formModel.canSubmit || formModel.isVerifying)
            default:
                EmptyView()
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
}

/// Inline form body (form without its own header/footer) — reused by both
/// the wizard's credentials step and `AddCameraForm`.
struct AddCameraFormBody: View {
    @ObservedObject var model: AddCameraFormModel

    var body: some View {
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

            Section("Events credentials (ONVIF — non-admin user, verified in Slice 5)") {
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
    }
}
