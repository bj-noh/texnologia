import SwiftUI
import AppKit

@main
struct TEXnologiaApp: App {
    @StateObject private var appModel = AppModel()

    var body: some Scene {
        WindowGroup {
            MainWindowView()
                .environmentObject(appModel)
        }
        .commands {
            CommandGroup(after: .newItem) {
                Button("Open Project...") {
                    appModel.openProjectPanel()
                }
                .keyboardShortcut("o", modifiers: [.command])

                Button("Import Zip Archive...") {
                    appModel.openZipPanel()
                }
                .keyboardShortcut("o", modifiers: [.command, .shift])
            }

            CommandGroup(replacing: .saveItem) {
                Button("Save and Compile") {
                    appModel.saveSelectedFileAndBuildIfNeeded()
                }
                .keyboardShortcut("s", modifiers: [.command])
            }

            CommandGroup(after: .windowSize) {
                Button("Toggle Full Screen") {
                    NSApp.keyWindow?.toggleFullScreen(nil)
                }
                .keyboardShortcut("f", modifiers: [.command, .control])
            }
        }

        Settings {
            PreferencesView(settings: Binding(
                get: { appModel.settings },
                set: { appModel.updateSettings($0) }
            ))
        }
    }
}
