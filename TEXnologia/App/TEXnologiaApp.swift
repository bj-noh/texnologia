import SwiftUI
import AppKit

@main
struct TEXnologiaApp: App {
    @StateObject private var appModel = AppModel()

    init() {
        if CommandLine.arguments.contains("--run-tests") {
            let code = TestRunner.runAll()
            Foundation.exit(code)
        }
    }

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

            CommandGroup(after: .textFormatting) {
                Divider()
                Button("Increase Font Size") {
                    appModel.adjustEditorFontSize(by: 1)
                }
                .keyboardShortcut("=", modifiers: [.command])

                Button("Decrease Font Size") {
                    appModel.adjustEditorFontSize(by: -1)
                }
                .keyboardShortcut("-", modifiers: [.command])

                Button("Reset Font Size") {
                    appModel.resetEditorFontSize()
                }
                .keyboardShortcut("0", modifiers: [.command])
            }

            CommandGroup(after: .textEditing) {
                Divider()
                Button("Find…") {
                    NotificationCenter.default.post(name: .editorPerformFind, object: nil)
                }
                .keyboardShortcut("f", modifiers: [.command])

                Button("Toggle Line Comment") {
                    NotificationCenter.default.post(name: .editorToggleComment, object: nil)
                }
                .keyboardShortcut("/", modifiers: [.command])

                Button("Select Line") {
                    NotificationCenter.default.post(name: .editorSelectCurrentLine, object: nil)
                }
                .keyboardShortcut("l", modifiers: [.command])

                Button("Duplicate Line") {
                    NotificationCenter.default.post(name: .editorDuplicateLine, object: nil)
                }
                .keyboardShortcut("d", modifiers: [.command, .shift])

                Button("Delete Line") {
                    NotificationCenter.default.post(name: .editorDeleteLine, object: nil)
                }
                .keyboardShortcut("k", modifiers: [.command, .shift])

                Button("Move Line Up") {
                    NotificationCenter.default.post(name: .editorMoveLineUp, object: nil)
                }
                .keyboardShortcut(.upArrow, modifiers: [.option])

                Button("Move Line Down") {
                    NotificationCenter.default.post(name: .editorMoveLineDown, object: nil)
                }
                .keyboardShortcut(.downArrow, modifiers: [.option])
            }
        }

        Settings {
            PreferencesHost(appModel: appModel)
        }
    }
}

private struct PreferencesHost: View {
    let appModel: AppModel
    @State private var settings: AppSettings

    init(appModel: AppModel) {
        self.appModel = appModel
        _settings = State(initialValue: appModel.settings)
    }

    var body: some View {
        PreferencesView(settings: $settings)
            .onChange(of: settings) { _, newValue in
                appModel.updateSettings(newValue)
            }
    }
}
