import Foundation

public enum BridgePath {
    public static var defaultSocketPath: String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return "\(home)/.clawdpet/bridge.sock"
    }

    public static func ensureParentDirectory(for socketPath: String) throws {
        let directory = URL(fileURLWithPath: socketPath).deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }
}
