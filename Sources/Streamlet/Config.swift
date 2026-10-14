import Foundation

struct StreamletConfig: Codable {
    struct KeyAccount: Codable { var name: String?; var apiKey: String }
    struct CodexAccount: Codable {
        var name: String?
        /// A CODEX_HOME directory containing auth.json (e.g. "~/.codex-work").
        var codexHome: String?
        var accessToken: String?
        var accountId: String?
    }
    struct DevinAccount: Codable { var name: String?; var token: String }

    var refreshMinutes: Double?
    var discoverCCSwitch: Bool?
    var discoverCodexCLI: Bool?
    var discoverOpenCodeAuth: Bool?
    var discoverDevinDesktop: Bool?
    var codex: [CodexAccount]?
    var opencodeGo: [KeyAccount]?
    var devin: [DevinAccount]?

    static let sample = StreamletConfig(
        refreshMinutes: 5,
        discoverCCSwitch: true,
        discoverCodexCLI: true,
        discoverOpenCodeAuth: true,
        discoverDevinDesktop: true,
        codex: [],
        opencodeGo: [],
        devin: []
    )
}

enum ConfigStore {
    static var directory: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".config/streamlet", isDirectory: true)
    }
    static var url: URL { directory.appendingPathComponent("config.json") }

    static func ensureExists() {
        let fm = FileManager.default
        guard !fm.fileExists(atPath: url.path) else { return }
        try? fm.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? enc.encode(StreamletConfig.sample) {
            fm.createFile(atPath: url.path, contents: data, attributes: [.posixPermissions: 0o600])
        }
    }

    static func load() -> (StreamletConfig, String?) {
        guard let data = try? Data(contentsOf: url) else { return (.sample, nil) }
        do { return (try JSONDecoder().decode(StreamletConfig.self, from: data), nil) }
        catch { return (.sample, "配置文件解析失败（已使用默认值）：\(error.localizedDescription)") }
    }
}

func expandTilde(_ path: String) -> String { (path as NSString).expandingTildeInPath }
