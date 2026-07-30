import SwiftUI

struct RootView: View {
    @EnvironmentObject private var store: AppStore

    var body: some View {
        Group {
            if store.configurationIsUnreadable {
                // Deliberately ahead of the `configuration == nil` branch: a workspace that
                // exists but can't be read must not land on the setup wizard, whose "Create
                // workspace" would overwrite it.
                WorkspaceRecoveryView()
            } else if store.configuration == nil {
                SetupWizardView()
            } else {
                WorkspaceView()
            }
        }
        .alert("Lesson Planner needs attention", isPresented: Binding(
            get: { store.lastError != nil && !store.configurationIsUnreadable },
            set: { if !$0 { store.lastError = nil } }
        )) {
            Button("OK", role: .cancel) { store.lastError = nil }
        } message: {
            Text(store.lastError ?? "")
        }
    }
}

/// Shown when a saved workspace exists but cannot be decoded. Its job is to keep the teacher's
/// data safe: explain plainly that nothing was lost, say where the file is, and offer only
/// non-destructive actions. Notably it does NOT offer "start a new workspace" — that is the
/// one action that would destroy the unreadable file.
private struct WorkspaceRecoveryView: View {
    @EnvironmentObject private var store: AppStore

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Your workspace could not be opened")
                .font(DS.font(30, weight: .semibold))
                .foregroundStyle(DS.text)

            Text("Your saved planning data is still on this Mac — it has not been deleted. This version of Lesson Planner could not read it, which usually means the app needs updating to understand a newer saved file.")
                .font(DS.font(14))
                .foregroundStyle(DS.neutral700)
                .fixedSize(horizontal: false, vertical: true)

            if let detail = store.lastError {
                DSCard {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Reported problem")
                            .font(DS.font(12, weight: .semibold))
                            .foregroundStyle(DS.text)
                        Text(detail)
                            .font(DS.font(13))
                            .foregroundStyle(DS.neutral700)
                            .textSelection(.enabled)
                    }
                }
            }

            DSCard {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Where your data is")
                        .font(DS.font(12, weight: .semibold))
                        .foregroundStyle(DS.text)
                    Text(LocalRepository().configurationURL().deletingLastPathComponent().path)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(DS.neutral700)
                        .textSelection(.enabled)
                    Text("Copy this folder somewhere safe before making changes.")
                        .font(DS.font(12))
                        .foregroundStyle(DS.neutral600)
                }
            }

            HStack(spacing: 10) {
                Button("Try again") { store.retryLoadingWorkspace() }
                    .buttonStyle(.dsPrimary)
                Button("Reveal data folder in Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([LocalRepository().configurationURL()])
                }
                .buttonStyle(.dsSecondary)
            }

            Text("Starting a new workspace is intentionally unavailable here, because it would overwrite the data that could not be read.")
                .font(DS.font(12))
                .foregroundStyle(DS.neutral600)
                .fixedSize(horizontal: false, vertical: true)

            Spacer()
        }
        .frame(maxWidth: 620, alignment: .leading)
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(DS.bg)
    }
}
