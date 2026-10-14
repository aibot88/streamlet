import Foundation

enum OpenCodeGo {
    struct Credential: Sendable { let name: String; let apiKey: String; let source: String }

    static let windows: [(String, String)] = [("rolling", "5 小时"), ("weekly", "每周"), ("monthly", "每月")]

    /// `GET https://opencode.ai/zen/go/v1/usage` → `{usage:{rolling|weekly|monthly:{percent, resetsAt}}}`
    /// (percent = used). Same endpoint cc-switch and OpenChamber read.
    static func parse(_ json: Any?) -> [UsageWindow] {
        guard let usage = J.obj(J.obj(json)?["usage"]) else { return [] }
        return windows.compactMap { key, label in
            guard let w = J.obj(usage[key]), let used = J.num(w["percent"]) else { return nil }
            // At 0% used upstream reports a placeholder now+window reset; hide it like cc-switch.
            let reset = used > 0 ? J.date(w["resetsAt"]) : nil
            return UsageWindow(label: label, remainingPercent: J.clampPercent(100 - used), resetAt: reset)
        }
    }

    static func fetch(_ c: Credential) async -> AccountUsage {
        var acc = AccountUsage(id: "go:" + sha256Hex(c.apiKey).prefix(12), kind: .opencodeGo, name: c.name,
                               subtitle: "\(c.source) · key \(maskKey(c.apiKey))")
        var req = URLRequest(url: URL(string: "https://opencode.ai/zen/go/v1/usage")!)
        req.setValue("Bearer \(c.apiKey)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue("Streamlet/1.0", forHTTPHeaderField: "User-Agent")
        do {
            let (code, data) = try await HTTP.send(req)
            switch code {
            case 200:
                acc.windows = parse(J.parse(data))
                if acc.windows.isEmpty { acc.error = "返回格式无法识别：\(HTTP.snippet(data))" }
            case 401: acc.error = "API key 无效 (HTTP 401)"
            case 403: acc.error = "key 有效但没有 OpenCode Go 订阅 (HTTP 403)"
            default: acc.error = "HTTP \(code)：\(HTTP.snippet(data))"
            }
        } catch { acc.error = "网络错误：\(error.localizedDescription)" }
        return acc
    }
}
