import Foundation

/// Offline checks of the parsers and the Electron decryption, run with `--selftest`.
enum SelfTest {
    static var failures = 0
    static func check(_ ok: Bool, _ name: String) {
        print((ok ? "PASS " : "FAIL ") + name)
        if !ok { failures += 1 }
    }

    static func run() -> Int32 {
        let go = OpenCodeGo.parse(J.parse(Data(#"{"usage":{"rolling":{"percent":2,"resetsAt":"2026-10-14T20:00:00Z"},"weekly":{"percent":58,"resetsAt":1792000000},"monthly":{"percent":"100","resetsAt":1792000000000},"status":"ok"}}"#.utf8)))
        check(go.map(\.label) == ["5 小时", "每周", "每月"], "opencode-go windows")
        check(go.map(\.remainingPercent) == [98, 42, 0], "opencode-go remaining = 100 - used")
        check(go[1].resetAt == Date(timeIntervalSince1970: 1_792_000_000) && go[2].resetAt == go[1].resetAt, "opencode-go reset seconds/ms")
        check(OpenCodeGo.parse(J.parse(Data(#"{"usage":{"rolling":{"percent":0,"resetsAt":1}}}"#.utf8)))[0].resetAt == nil, "opencode-go hides placeholder reset at 0%")

        let cx = Codex.parse(J.parse(Data(#"{"plan_type":"plus","rate_limit":{"primary_window":{"used_percent":0,"limit_window_seconds":18000,"reset_at":1792000000},"secondary_window":{"used_percent":73,"limit_window_seconds":604800,"reset_at":1792400000}},"credits":{"has_credits":true,"unlimited":false,"balance":"62500"}}"#.utf8)))
        check(cx.windows.map(\.label) == ["5 小时", "每周"] && cx.windows.map(\.remainingPercent) == [100, 27], "codex windows")
        check(cx.plan == "plus" && cx.credits == "Credits 余额：62500", "codex plan + credits")
        check(Codex.countResetCredits(J.parse(Data(#"{"credits":[{"status":"available","expires_at":"2099-01-01T00:00:00Z"},{"status":"available"},{"status":"used"},{"status":"available","expires_at":"2000-01-01T00:00:00Z"}]}"#.utf8))) == 2, "codex reset credits count")
        let auth = Codex.parseAuth(Data(#"{"auth_mode":"chatgpt","tokens":{"access_token":"a.eyJlbWFpbCI6ImFAYi5jIn0.c","account_id":"acc_1"}}"#.utf8), source: "t", name: nil)
        check(auth?.accountId == "acc_1" && auth?.email == "a@b.c", "codex auth.json + JWT email")
        check(Codex.parseAuth(Data(#"{"auth_mode":"apikey","OPENAI_API_KEY":"sk"}"#.utf8), source: "t", name: nil) == nil, "codex api-key mode skipped")

        let dv = Devin.parse(J.parse(Data(#"{"userStatus":{"name":"aibot","email":"x@y.z","planStatus":{"planInfo":{"planName":"Pro"},"weeklyQuotaRemainingPercent":38,"dailyQuotaResetAtUnix":"1792000000","weeklyQuotaResetAtUnix":"1792400000","overageBalanceMicros":"12500000"}}}"#.utf8)))
        check(dv.windows.map(\.label) == ["每日", "每周"] && dv.windows.map(\.remainingPercent) == [0, 38], "devin daily/weekly (omitted zero = 0%)")
        check(dv.plan == "Pro" && dv.email == "x@y.z" && dv.notes == ["额外余额 $12.50"], "devin plan/email/overage")

        let key = CCSwitch.extractKey(J.parse(Data(#"{"auth":{"OPENAI_API_KEY":"sk-go-1"},"config":"base_url = \"https://opencode.ai/zen/go/v1\""}"#.utf8)))
        let key2 = CCSwitch.extractKey(J.parse(Data(#"{"env":{"ANTHROPIC_BASE_URL":"https://opencode.ai/zen/go","ANTHROPIC_AUTH_TOKEN":"sk-go-2"}}"#.utf8)))
        let key3 = CCSwitch.extractKey(J.parse(Data(#"{"auth":{},"config":"experimental_bearer_token = \"sk-go-3\""}"#.utf8)))
        check(key == "sk-go-1" && key2 == "sk-go-2" && key3 == "sk-go-3", "cc-switch key extraction")

        let sessions = #"[{"id":"1","accessToken":"devin-session-token$abcdefgh123","account":{"label":"me@x.com","id":"u"},"scopes":[]}]"#
        if let enc = ElectronSafeStorage.encrypt(sessions, password: "pw-123"),
           let rec = try? JSONSerialization.data(withJSONObject: ["type": "Buffer", "data": enc.map { Int($0) }]),
           let bytes = ElectronSafeStorage.bufferBytes(rec),
           let plain = ElectronSafeStorage.decrypt(bytes, password: "pw-123") {
            let creds = Devin.parseSessions(plain, source: "t")
            check(creds.count == 1 && creds[0].name == "me@x.com" && creds[0].token.hasPrefix("devin-session-token$"), "electron safeStorage roundtrip + sessions")
            check(ElectronSafeStorage.decrypt(bytes, password: "wrong") == nil, "electron wrong password rejected")
        } else { check(false, "electron safeStorage roundtrip") }

        let now = Date()
        check(formatCountdown(now.addingTimeInterval(4 * 86400 + 7 * 3600 + 30), now: now) == "4d7h"
              && formatCountdown(now.addingTimeInterval(5 * 3600 + 10), now: now) == "5h0m", "countdown format")

        print(failures == 0 ? "ALL PASS" : "\(failures) FAILED")
        return failures == 0 ? 0 : 1
    }
}
