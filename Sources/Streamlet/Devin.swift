import Foundation

enum Devin {
    struct Credential: Sendable { let name: String?; let token: String; let source: String }

    struct DesktopApp { let label: String; let dir: String; let service: String; let account: String }

    static let storageKey = #"secret://{"extensionId":"codeium.windsurf","key":"windsurf_auth.sessions"}"#
    static let desktopApps = [
        DesktopApp(label: "Devin Desktop", dir: "~/Library/Application Support/Devin", service: "Devin Safe Storage", account: "Devin Key"),
        DesktopApp(label: "Windsurf", dir: "~/Library/Application Support/Windsurf", service: "Windsurf Safe Storage", account: "Windsurf Key"),
    ]

    /// Devin Desktop (Windsurf-based Electron app) stores its sign-in sessions in
    /// globalStorage/state.vscdb, encrypted with Electron safeStorage whose
    /// password lives in the login Keychain.
    static func desktopCredentials() -> ([Credential], [String]) {
        var creds: [Credential] = [], problems: [String] = []
        for app in desktopApps {
            let db = expandTilde(app.dir) + "/User/globalStorage/state.vscdb"
            guard FileManager.default.fileExists(atPath: db) else { continue }
            guard let rows = SQLiteReader.rows(path: db, sql: "SELECT value FROM ItemTable WHERE key = ? LIMIT 1", args: [storageKey], immutable: true),
                  let record = rows.first?["value"], !record.isEmpty else {
                continue // installed but not signed in
            }
            let password: String
            switch Keychain.password(service: app.service, account: app.account) {
            case .found(let p): password = p
            case .notFound: problems.append("\(app.label)：Keychain 中没有「\(app.service)」"); continue
            case .failed(let m): problems.append("\(app.label)：读取 Keychain「\(app.service)」被拒绝（\(m)）"); continue
            }
            guard let bytes = ElectronSafeStorage.bufferBytes(record),
                  let plain = ElectronSafeStorage.decrypt(bytes, password: password) else {
                problems.append("\(app.label)：登录记录解密失败"); continue
            }
            let found = parseSessions(plain, source: app.label)
            if found.isEmpty { problems.append("\(app.label)：登录记录里没有 accessToken") }
            creds += found
        }
        return (creds, problems)
    }

    static func parseSessions(_ plain: String, source: String) -> [Credential] {
        guard let arr = J.parse(Data(plain.utf8)) as? [Any] else { return [] }
        return arr.compactMap(J.obj).compactMap { s in
            guard let token = J.str(s["accessToken"]) else { return nil }
            let label = J.str(J.obj(s["account"])?["label"])
            return Credential(name: label, token: token, source: source)
        }
    }

    /// The windsurf.com usage page renders `planStatus.{daily,weekly}QuotaRemainingPercent`
    /// and `{daily,weekly}QuotaResetAtUnix`. The desktop session token is accepted
    /// by SeatManagementService/GetUserStatus as `metadata.apiKey`.
    static func parse(_ json: Any?) -> (name: String?, email: String?, plan: String?, windows: [UsageWindow], notes: [String]) {
        let root = J.obj(json) ?? [:]
        let user = J.obj(root["userStatus"]) ?? [:]
        let ps = J.obj(user["planStatus"]) ?? J.obj(root["planStatus"]) ?? [:]
        let plan = J.str(J.obj(ps["planInfo"])?["planName"]) ?? J.str(J.obj(root["planInfo"])?["planName"])
        var windows: [UsageWindow] = []
        // proto3 JSON omits zero values: a reset time without a percent means 0% left.
        for (label, pKey, rKey) in [("每日", "dailyQuotaRemainingPercent", "dailyQuotaResetAtUnix"),
                                    ("每周", "weeklyQuotaRemainingPercent", "weeklyQuotaResetAtUnix")] {
            let pct = J.num(ps[pKey]), reset = J.date(ps[rKey])
            if pct == nil && reset == nil { continue }
            windows.append(UsageWindow(label: label, remainingPercent: J.clampPercent(pct ?? 0), resetAt: reset))
        }
        var notes: [String] = []
        if let micros = J.num(ps["overageBalanceMicros"]), micros > 0 {
            notes.append(String(format: "额外余额 $%.2f", micros / 1_000_000))
        }
        if let used = J.num(ps["acuConsumed"]), let limit = J.num(ps["acuLimit"]), limit > 0 {
            notes.append(String(format: "ACU %.1f / %.0f", used, limit))
        }
        if windows.isEmpty, let avail = J.num(ps["availablePromptCredits"]), avail > 0 {
            let used = J.num(ps["usedPromptCredits"]) ?? 0
            windows.append(UsageWindow(label: "积分", remainingPercent: J.clampPercent((avail - used) / avail * 100),
                                       resetAt: J.date(J.obj(ps["planEnd"]).flatMap { J.num($0["seconds"]) })))
            notes.append(String(format: "积分 %.0f / %.0f", (avail - used) / 100, avail / 100))
        }
        return (J.str(user["name"]), J.str(user["email"]), plan, windows, notes)
    }

    static func fetch(_ c: Credential) async -> AccountUsage {
        var acc = AccountUsage(id: "devin:" + sha256Hex(c.token).prefix(12), kind: .devin,
                               name: c.name ?? "Devin", subtitle: c.source)
        var req = URLRequest(url: URL(string: "https://server.codeium.com/exa.seat_management_pb.SeatManagementService/GetUserStatus")!)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("1", forHTTPHeaderField: "Connect-Protocol-Version")
        let body: [String: Any] = ["metadata": [
            "apiKey": c.token, "ideName": "windsurf", "ideVersion": "2026.8.18",
            "extensionName": "windsurf", "extensionVersion": "2026.8.18", "locale": "zh-CN", "os": "darwin",
        ]]
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        do {
            let (code, data) = try await HTTP.send(req)
            if code == 200 {
                let p = parse(J.parse(data))
                if let n = p.name, c.name == nil { acc.name = n }
                acc.subtitle = [p.email, c.source].compactMap { $0 }.joined(separator: " · ")
                acc.badge = p.plan
                acc.windows = p.windows
                acc.notes = p.notes
                if acc.windows.isEmpty { acc.notes.append("该账号未返回 Daily/Weekly 配额") }
            } else {
                let msg = J.str(J.obj(J.parse(data))?["message"]) ?? HTTP.snippet(data)
                acc.error = code == 401 ? "登录失效，请在 Devin Desktop 重新登录：\(msg)" : "HTTP \(code)：\(msg)"
            }
        } catch { acc.error = "网络错误：\(error.localizedDescription)" }
        return acc
    }
}
