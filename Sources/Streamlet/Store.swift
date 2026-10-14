import AppKit
import Foundation
import ServiceManagement

enum Collector {
    static func collect() async -> ([AccountUsage], [String]) {
        let (cfg, cfgError) = ConfigStore.load()
        var problems: [String] = cfgError.map { [$0] } ?? []

        // Credential discovery touches files and Keychain; keep it off the main actor.
        let (codex, go, devin, devinProblems) = await Task.detached { () -> ([Codex.Credential], [OpenCodeGo.Credential], [Devin.Credential], [String]) in
            var codex: [Codex.Credential] = [], go: [OpenCodeGo.Credential] = [], devin: [Devin.Credential] = []
            var probs: [String] = []
            for a in cfg.codex ?? [] {
                if let t = a.accessToken {
                    codex.append(.init(name: a.name, accessToken: t, accountId: a.accountId, email: JWT.email(t), source: "config", stale: false))
                } else if let h = a.codexHome {
                    let (c, p) = Codex.credential(home: expandTilde(h), name: a.name)
                    if let c { codex.append(c) } else { probs.append(p ?? "Codex：\(h) 下没有登录") }
                }
            }
            if cfg.discoverCodexCLI ?? true {
                let (c, p) = Codex.credential(home: Codex.defaultHome(), name: nil)
                if let c { codex.append(c) } else if let p { probs.append(p) }
            }
            go += (cfg.opencodeGo ?? []).map { .init(name: $0.name ?? "OpenCode Go", apiKey: $0.apiKey, source: "config") }
            if cfg.discoverCCSwitch ?? true { go += CCSwitch.opencodeGoCredentials() }
            if cfg.discoverOpenCodeAuth ?? true { go += OpenCodeAuthFile.credentials() }
            devin += (cfg.devin ?? []).map { .init(name: $0.name, token: $0.token, source: "config") }
            if cfg.discoverDevinDesktop ?? true {
                let (d, p) = Devin.desktopCredentials()
                devin += d; probs += p
            }
            return (dedupe(codex) { $0.accountId ?? $0.accessToken }, dedupe(go) { $0.apiKey }, dedupe(devin) { $0.token }, probs)
        }.value
        problems += devinProblems

        var jobs: [@Sendable () async -> AccountUsage] = []
        jobs += codex.map { c in { await Codex.fetch(c) } }
        jobs += go.map { c in { await OpenCodeGo.fetch(c) } }
        jobs += devin.map { c in { await Devin.fetch(c) } }
        let results = await withTaskGroup(of: (Int, AccountUsage).self) { group in
            for (i, job) in jobs.enumerated() { group.addTask { (i, await job()) } }
            var out: [(Int, AccountUsage)] = []
            for await r in group { out.append(r) }
            return out.sorted { $0.0 < $1.0 }.map(\.1)
        }
        return (results, problems)
    }

    static func dedupe<T>(_ items: [T], key: (T) -> String) -> [T] {
        var seen = Set<String>()
        return items.filter { seen.insert(key($0)).inserted }
    }
}

@MainActor
final class UsageStore: ObservableObject {
    @Published var accounts: [AccountUsage] = []
    @Published var problems: [String] = []
    @Published var loading = false
    @Published var lastUpdated: Date?
    @Published var launchAtLogin = SMAppService.mainApp.status == .enabled

    private var timer: Timer?
    let demo = ProcessInfo.processInfo.arguments.contains("--demo") || ProcessInfo.processInfo.environment["STREAMLET_DEMO"] == "1"

    init() {
        ConfigStore.ensureExists()
        Task { await refresh() }
        let minutes = max(1, ConfigStore.load().0.refreshMinutes ?? 5)
        timer = Timer.scheduledTimer(withTimeInterval: minutes * 60, repeats: true) { [weak self] _ in
            Task { await self?.refresh() }
        }
    }

    var lowestRemaining: Double? {
        accounts.flatMap(\.windows).map(\.remainingPercent).min()
    }

    func refresh() async {
        guard !loading else { return }
        loading = true
        defer { loading = false }
        if demo {
            accounts = DemoData.accounts; problems = []
        } else {
            (accounts, problems) = await Collector.collect()
        }
        lastUpdated = Date()
    }

    func refreshIfStale() {
        if let t = lastUpdated, Date().timeIntervalSince(t) < 60 { return }
        Task { await refresh() }
    }

    func openConfig() {
        ConfigStore.ensureExists()
        NSWorkspace.shared.open(ConfigStore.url)
    }

    func setLaunchAtLogin(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            problems.append("开机启动设置失败：\(error.localizedDescription)")
        }
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }
}

enum DemoData {
    static var accounts: [AccountUsage] {
        let now = Date()
        func w(_ l: String, _ p: Double, _ secs: Double?) -> UsageWindow {
            UsageWindow(label: l, remainingPercent: p, resetAt: secs.map { now.addingTimeInterval($0) })
        }
        return [
            AccountUsage(id: "d1", kind: .codex, name: "OpenAI Official", subtitle: "you@example.com · Keychain", badge: "Plus",
                         windows: [w("5 小时", 100, 5 * 3600), w("每周", 27, 5 * 86400 + 12 * 3600)], notes: ["可用重置 3 次"]),
            AccountUsage(id: "d2", kind: .opencodeGo, name: "OpenCode Go1", subtitle: "cc-switch/codex · key …a1b2",
                         windows: [w("5 小时", 100, nil), w("每周", 100, nil), w("每月", 100, nil)]),
            AccountUsage(id: "d3", kind: .opencodeGo, name: "OpenCode Go 2", subtitle: "cc-switch/codex · key …c3d4",
                         windows: [w("5 小时", 100, nil), w("每周", 95, 4 * 86400 + 7 * 3600), w("每月", 0, 4 * 86400 + 7 * 3600)]),
            AccountUsage(id: "d4", kind: .opencodeGo, name: "OpenCode Go 3", subtitle: "cc-switch/codex · key …e5f6",
                         windows: [w("5 小时", 98, 4 * 3600), w("每周", 42, 4 * 86400 + 7 * 3600), w("每月", 21, 4 * 86400 + 7 * 3600)]),
            AccountUsage(id: "d5", kind: .devin, name: "aibot", subtitle: "you@example.com · Devin Desktop", badge: "Pro",
                         windows: [w("每日", 64, 9 * 3600), w("每周", 38, 3 * 86400 + 2 * 3600)], notes: ["额外余额 $12.50"]),
        ]
    }
}
