import Foundation

enum Codex {
    struct Credential: Sendable {
        let name: String?
        let accessToken: String
        let accountId: String?
        let email: String?
        let source: String
        let stale: Bool
    }

    static func defaultHome() -> String {
        if let h = ProcessInfo.processInfo.environment["CODEX_HOME"], !h.isEmpty { return expandTilde(h) }
        return expandTilde("~/.codex")
    }

    /// Codex CLI keeps the login either in Keychain (service "Codex Auth",
    /// account "cli|" + sha256(canonical CODEX_HOME)[0..16]) or in auth.json.
    /// Tokens are only read, never refreshed, so a refresh-token rotation can
    /// never sign out Codex CLI or cc-switch.
    static func credential(home: String, name: String?) -> (Credential?, String?) {
        let canonical = (try? FileManager.default.destinationOfSymbolicLink(atPath: home)).map(expandTilde) ?? home
        let resolved = URL(fileURLWithPath: canonical).resolvingSymlinksInPath().path
        let account = "cli|" + sha256Hex(resolved).prefix(16)
        if case .found(let secret) = Keychain.password(service: "Codex Auth", account: account),
           let c = parseAuth(Data(secret.utf8), source: "Keychain", name: name) {
            return (c, nil)
        }
        let file = (home as NSString).appendingPathComponent("auth.json")
        guard let data = FileManager.default.contents(atPath: file) else { return (nil, nil) }
        guard let c = parseAuth(data, source: (file as NSString).abbreviatingWithTildeInPath, name: name) else {
            return (nil, "\(file) 不是 ChatGPT 登录（API key 模式没有订阅用量）")
        }
        return (c, nil)
    }

    static func parseAuth(_ data: Data, source: String, name: String?) -> Credential? {
        guard let o = J.obj(J.parse(data)) else { return nil }
        if let mode = J.str(o["auth_mode"]), !mode.lowercased().hasPrefix("chatgpt") { return nil }
        guard let t = J.obj(o["tokens"]), let at = J.str(t["access_token"]) else { return nil }
        let idToken = J.str(t["id_token"]) ?? J.str(J.obj(t["id_token"])?["raw_jwt"])
        let email = idToken.flatMap(JWT.email) ?? JWT.email(at)
        var stale = false
        if let lr = J.date(o["last_refresh"]) { stale = Date().timeIntervalSince(lr) > 8 * 86400 }
        if let exp = J.num(JWT.payload(at)?["exp"]) { stale = stale || Date(timeIntervalSince1970: exp) < Date() }
        return Credential(name: name, accessToken: at, accountId: J.str(t["account_id"]), email: email, source: source, stale: stale)
    }

    static func label(seconds: Double?) -> String {
        guard let s = seconds else { return "窗口" }
        switch Int(s) {
        case 18000: return "5 小时"
        case 86400: return "每日"
        case 604800: return "每周"
        case 2_592_000: return "每月"
        default:
            let h = Int(s) / 3600
            return h >= 24 ? "\(h / 24) 天" : "\(h) 小时"
        }
    }

    /// `GET chatgpt.com/backend-api/wham/usage` → rate_limit.{primary,secondary}_window
    static func parse(_ json: Any?) -> (windows: [UsageWindow], plan: String?, credits: String?) {
        let root = J.obj(json) ?? [:]
        let rl = J.obj(root["rate_limit"]) ?? [:]
        var windows: [UsageWindow] = []
        for key in ["primary_window", "secondary_window"] {
            guard let w = J.obj(rl[key]), let used = J.num(w["used_percent"]) else { continue }
            var reset = J.date(w["reset_at"])
            if reset == nil, let after = J.num(w["reset_after_seconds"]) { reset = Date().addingTimeInterval(after) }
            windows.append(UsageWindow(label: label(seconds: J.num(w["limit_window_seconds"])),
                                       remainingPercent: J.clampPercent(100 - used), resetAt: reset))
        }
        var credits: String?
        if let c = J.obj(root["credits"]), (c["has_credits"] as? Bool) == true {
            if (c["unlimited"] as? Bool) == true { credits = "Credits：无限" }
            else if let b = J.num(c["balance"]), b > 0 { credits = "Credits 余额：\(Int(b))" }
        }
        return (windows, J.str(root["plan_type"]), credits)
    }

    static func countResetCredits(_ json: Any?) -> Int? {
        guard let arr = J.obj(json)?["credits"] as? [Any] else { return nil }
        return arr.compactMap(J.obj).filter { e in
            guard J.str(e["status"]) == "available" else { return false }
            if let exp = J.date(e["expires_at"]) { return exp > Date() }
            return true
        }.count
    }

    static func request(_ path: String, _ c: Credential) -> URLRequest {
        var req = URLRequest(url: URL(string: "https://chatgpt.com/backend-api/" + path)!)
        req.setValue("Bearer \(c.accessToken)", forHTTPHeaderField: "Authorization")
        req.setValue("codex-cli", forHTTPHeaderField: "User-Agent")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        if let id = c.accountId { req.setValue(id, forHTTPHeaderField: "ChatGPT-Account-Id") }
        return req
    }

    static func fetch(_ c: Credential) async -> AccountUsage {
        var acc = AccountUsage(id: "codex:" + (c.accountId ?? sha256Hex(c.accessToken).prefix(12).description),
                               kind: .codex, name: c.name ?? "OpenAI Official",
                               subtitle: [c.email, c.source].compactMap { $0 }.joined(separator: " · "))
        async let resetCreditsResp = try? HTTP.send(request("wham/rate-limit-reset-credits", c))
        do {
            let (code, data) = try await HTTP.send(request("wham/usage", c))
            switch code {
            case 200:
                let p = parse(J.parse(data))
                acc.windows = p.windows
                acc.badge = p.plan?.capitalized
                if let cr = p.credits { acc.notes.append(cr) }
                if acc.windows.isEmpty { acc.error = "返回中没有限额窗口：\(HTTP.snippet(data))" }
            case 401, 403:
                acc.error = c.stale ? "登录已过期，请运行一次 codex 或在 cc-switch 里重新登录 (HTTP \(code))"
                                    : "认证失败 (HTTP \(code))：\(HTTP.snippet(data))"
            default: acc.error = "HTTP \(code)：\(HTTP.snippet(data))"
            }
        } catch { acc.error = "网络错误：\(error.localizedDescription)" }
        if acc.error == nil, let (code, data) = await resetCreditsResp, code == 200,
           let n = countResetCredits(J.parse(data)), n > 0 {
            acc.notes.append("可用重置 \(n) 次")
        }
        return acc
    }
}
