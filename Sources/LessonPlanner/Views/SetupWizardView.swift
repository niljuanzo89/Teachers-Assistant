import AppKit
import SwiftUI

struct SetupWizardView: View {
    @EnvironmentObject private var store: AppStore
    @State private var workspaceName = "My Planning Workspace"
    @State private var workspaceURL: URL?
    @State private var outputURL: URL?
    @State private var templateURL: URL?
    @State private var sourceURLs: [URL] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Welcome to Lesson Planner")
                .font(.largeTitle.bold())
            Text("Set up a local workspace. Phase 1 registers files and folders only; it does not read curriculum content.")
                .foregroundStyle(.secondary)

            Form {
                TextField("Workspace name", text: $workspaceName)
                FilePickerRow(title: "App workspace", selection: $workspaceURL, chooseDirectories: true, required: true)
                FilePickerRow(title: "Output folder", selection: $outputURL, chooseDirectories: true)
                FilePickerRow(title: "Weekly-plan HTML template", selection: $templateURL, chooseDirectories: false)
                HStack(alignment: .top) {
                    Text("Source folders")
                    Spacer()
                    VStack(alignment: .trailing) {
                        ForEach(sourceURLs, id: \.self) { url in
                            HStack {
                                Text(url.path).lineLimit(1).truncationMode(.middle)
                                Button("Remove") { sourceURLs.removeAll { $0 == url } }
                            }
                        }
                        Button("Add source folder…") { addSourceFolder() }
                    }
                }
            }

            Text("Everything remains local. No account, network connection, curriculum parsing, or AI provider is used in this phase.")
                .font(.footnote)
                .foregroundStyle(.secondary)

            HStack {
                Spacer()
                Button("Create workspace") {
                    guard let workspaceURL else { return }
                    store.completeSetup(workspaceName: workspaceName, workspaceURL: workspaceURL, outputURL: outputURL, templateURL: templateURL, sourceURLs: sourceURLs)
                }
                .buttonStyle(.borderedProminent)
                .disabled(workspaceURL == nil || workspaceName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(32)
        .frame(maxWidth: 700, alignment: .leading)
    }

    private func addSourceFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = true
        if panel.runModal() == .OK {
            sourceURLs.append(contentsOf: panel.urls.filter { !sourceURLs.contains($0) })
        }
    }
}

private struct FilePickerRow: View {
    let title: String
    @Binding var selection: URL?
    let chooseDirectories: Bool
    var required = false

    var body: some View {
        HStack {
            Text(required ? "\(title) *" : title)
            Spacer()
            Text(selection?.path ?? "Not selected")
                .foregroundStyle(selection == nil ? .secondary : .primary)
                .lineLimit(1)
                .truncationMode(.middle)
            Button("Choose…") { choose() }
        }
    }

    private func choose() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = chooseDirectories
        panel.canChooseFiles = !chooseDirectories
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = chooseDirectories
        if panel.runModal() == .OK { selection = panel.url }
    }
}
