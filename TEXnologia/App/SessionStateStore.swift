import Foundation

struct SessionStateSnapshot: Codable {
    struct WorkspaceEntry: Codable {
        var id: WorkspaceID
        var rootPath: String
        var displayName: String
        var mainFilePath: String?
        var openTabPaths: [String]
        var activeTabPath: String?
    }

    var version: Int = 1
    var workspaces: [WorkspaceEntry]
    var activeWorkspaceID: WorkspaceID?
    var isChatPaneVisible: Bool
}

enum SessionStateStore {
    private static let fileName = "session-state.json"

    static func save(_ snapshot: SessionStateSnapshot) {
        guard let url = storageURL() else { return }
        do {
            let data = try JSONEncoder().encode(snapshot)
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try data.write(to: url, options: [.atomic])
        } catch {
            NSLog("[SessionStateStore] Failed to save: \(error.localizedDescription)")
        }
    }

    static func load() -> SessionStateSnapshot? {
        guard let url = storageURL(),
              FileManager.default.fileExists(atPath: url.path) else { return nil }
        do {
            let data = try Data(contentsOf: url)
            return try JSONDecoder().decode(SessionStateSnapshot.self, from: data)
        } catch {
            NSLog("[SessionStateStore] Failed to load: \(error.localizedDescription)")
            return nil
        }
    }

    private static func storageURL() -> URL? {
        guard let support = try? FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ) else { return nil }

        return support
            .appendingPathComponent("TEXnologia", isDirectory: true)
            .appendingPathComponent(fileName)
    }
}
