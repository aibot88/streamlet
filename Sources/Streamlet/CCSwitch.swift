import Foundation

/// Read-only discovery of accounts configured in cc-switch (~/.cc-switch/cc-switch.db).
enum CCSwitch {
    static var dbPath: String { expandTilde("~/.cc-switch/cc-switch.db") }

    static func opencodeGoCredentials() -> [OpenCodeGo.Credential] {
        guard let rows = SQLiteReader.rows(
            path: dbPath,
            sql: "SELECT name, app_type, settings_config FROM providers WHERE settings_config LIKE '%opencode.ai/zen/go%' ORDER BY COALESCE(sort_index, 999999), created_at"
        ) else { return [] }
        var out: [OpenCodeGo.Credential] = []
        for r in rows {
            let name = String(decoding: r["name"] ?? Data(), as: UTF8.self)
            let app = String(decoding: r["app_type"] ?? Data(), as: UTF8.self)
            guard let cfg = r["settings_config"], let key = extractKey(J.parse(cfg)) else { continue }
            out.append(.init(name: name.isEmpty ? "OpenCode Go" : name, apiKey: key, source: "cc-switch/\(app)"))
        }
        return out
    }

    /// Mirrors cc-switch's per-app credential layout (UsageScriptModal / resolve_usage_credentials).
    static func extractKey(_ json: Any?) -> String? {
        guard let root = J.obj(json) else { return nil }
        let env = J.obj(root["env"]) ?? [:]
        let auth = J.obj(root["auth"]) ?? [:]
        let options = J.obj(root["options"]) ?? [:]
        let candidates: [Any?] = [
            auth["OPENAI_API_KEY"], env["ANTHROPIC_AUTH_TOKEN"], env["ANTHROPIC_API_KEY"], env["OPENAI_API_KEY"],
            options["apiKey"], root["apiKey"], root["api_key"],
        ]
        for c in candidates { if let s = J.str(c) { return s.trimmingCharacters(in: .whitespaces) } }
        if let toml = J.str(root["config"]),
           let m = toml.range(of: #"experimental_bearer_token\s*=\s*"([^"]+)""#, options: .regularExpression) {
            let line = String(toml[m])
            if let q1 = line.firstIndex(of: "\""), let q2 = line.lastIndex(of: "\""), q1 < q2 {
                return String(line[line.index(after: q1)..<q2])
            }
        }
        return nil
    }
}

/// OpenCode CLI's own credential file, if the user signed in to Go with an API key there.
enum OpenCodeAuthFile {
    static func credentials() -> [OpenCodeGo.Credential] {
        let path = expandTilde("~/.local/share/opencode/auth.json")
        guard let data = FileManager.default.contents(atPath: path), let root = J.obj(J.parse(data)),
              let entry = J.obj(root["opencode-go"]),
              let key = J.str(entry["key"]) ?? J.str(entry["token"]) else { return [] }
        return [.init(name: "OpenCode Go (opencode auth)", apiKey: key, source: "opencode")]
    }
}
