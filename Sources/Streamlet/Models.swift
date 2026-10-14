import Foundation

enum ProviderKind: String, CaseIterable, Sendable {
    case codex, opencodeGo, devin

    var title: String {
        switch self {
        case .codex: return "Codex · OpenAI"
        case .opencodeGo: return "OpenCode Go"
        case .devin: return "Devin"
        }
    }
}

struct UsageWindow: Identifiable, Hashable, Sendable {
    var id: String { label }
    let label: String
    /// 0...100, remaining share of the window.
    let remainingPercent: Double
    let resetAt: Date?
}

struct AccountUsage: Identifiable, Sendable {
    let id: String
    let kind: ProviderKind
    var name: String
    var subtitle: String?
    var badge: String?
    var windows: [UsageWindow] = []
    var notes: [String] = []
    var error: String?
}

/// Lenient JSON value helpers: upstream APIs mix numbers, numeric strings,
/// unix seconds, unix milliseconds and ISO-8601 strings.
enum J {
    static func obj(_ v: Any?) -> [String: Any]? { v as? [String: Any] }

    static func str(_ v: Any?) -> String? {
        guard let s = v as? String, !s.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        return s
    }

    static func num(_ v: Any?) -> Double? {
        if let n = v as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID() { return n.doubleValue }
        if let s = v as? String { return Double(s.trimmingCharacters(in: .whitespaces)) }
        return nil
    }

    static func date(_ v: Any?) -> Date? {
        if let n = num(v), n > 0 {
            return Date(timeIntervalSince1970: n > 1e12 ? n / 1000 : n)
        }
        if let s = str(v) {
            let f1 = ISO8601DateFormatter()
            f1.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let d = f1.date(from: s) { return d }
            let f2 = ISO8601DateFormatter()
            if let d = f2.date(from: s) { return d }
        }
        return nil
    }

    static func parse(_ data: Data) -> Any? { try? JSONSerialization.jsonObject(with: data) }

    static func clampPercent(_ v: Double) -> Double { min(100, max(0, v)) }
}

enum HTTP {
    static let session: URLSession = {
        let c = URLSessionConfiguration.ephemeral
        c.timeoutIntervalForRequest = 15
        c.timeoutIntervalForResource = 30
        return URLSession(configuration: c)
    }()

    static func send(_ req: URLRequest) async throws -> (Int, Data) {
        let (data, resp) = try await session.data(for: req)
        return ((resp as? HTTPURLResponse)?.statusCode ?? 0, data)
    }

    static func snippet(_ data: Data) -> String {
        let s = String(decoding: data.prefix(240), as: UTF8.self)
        return s.replacingOccurrences(of: "\n", with: " ")
    }
}

enum JWT {
    static func payload(_ token: String) -> [String: Any]? {
        let parts = token.split(separator: ".")
        guard parts.count >= 2 else { return nil }
        var b64 = String(parts[1]).replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while b64.count % 4 != 0 { b64 += "=" }
        guard let data = Data(base64Encoded: b64) else { return nil }
        return J.obj(J.parse(data))
    }

    static func email(_ token: String) -> String? {
        guard let p = payload(token) else { return nil }
        if let e = J.str(p["email"]) { return e }
        return J.str(J.obj(p["https://api.openai.com/profile"])?["email"])
    }
}

func formatCountdown(_ date: Date, now: Date = Date()) -> String {
    let secs = Int(date.timeIntervalSince(now))
    if secs <= 0 { return "即将重置" }
    let d = secs / 86400, h = (secs % 86400) / 3600, m = (secs % 3600) / 60
    if d > 0 { return "\(d)d\(h)h" }
    if h > 0 { return "\(h)h\(m)m" }
    return "\(max(m, 1))m"
}
