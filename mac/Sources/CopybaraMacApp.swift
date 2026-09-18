import SwiftUI

@main
struct CopybaraMacApp: App {
    @StateObject private var controller = ClipController()

    var body: some Scene {
        MenuBarExtra {
            VStack(alignment: .leading, spacing: 8) {
                Text("Copybara 🦫")
                    .font(.headline)

                Label(controller.statusText, systemImage: controller.isConnected ? "checkmark.circle.fill" : "circle.dashed")
                    .foregroundStyle(controller.isConnected ? .green : .secondary)

                if !controller.lastSent.isEmpty {
                    Divider()
                    Text("Last sent:")
                        .font(.caption).foregroundStyle(.secondary)
                    Text(controller.lastSent)
                        .font(.caption)
                        .lineLimit(2)
                }

                Divider()

                Toggle("Sync clipboard to iPad", isOn: $controller.enabled)

                Button("Send current clipboard now") {
                    controller.sendCurrentClipboard(force: true)
                }
                .disabled(!controller.isConnected)

                Divider()

                Button("Quit Copybara") { NSApplication.shared.terminate(nil) }
            }
            .padding(12)
            .frame(width: 260)
        } label: {
            Image(systemName: controller.isConnected ? "doc.on.clipboard.fill" : "doc.on.clipboard")
        }
        .menuBarExtraStyle(.window)
    }
}
