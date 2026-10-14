# Streamlet

macOS 菜单栏小插件（小溪图标），集中显示多账号订阅用量：

| 服务 | 窗口 | 数据来源 |
| --- | --- | --- |
| Codex（ChatGPT 登录） | 5 小时 / 每周（+ Credits、可用重置次数） | `GET chatgpt.com/backend-api/wham/usage` |
| OpenCode Go | 5 小时 / 每周 / 每月 | `GET opencode.ai/zen/go/v1/usage`（与 cc-switch 相同） |
| Devin | 每日 / 每周（+ 额外余额） | `GetUserStatus` → `planStatus.daily/weeklyQuotaRemainingPercent`（与 windsurf.com/subscription/usage 相同） |

百分比均为**剩余**额度，右侧为重置倒计时；<30% 橙色，<10% 红色。

## 账号自动发现（只读，不刷新 / 不改写任何 token）

- **cc-switch**：`~/.cc-switch/cc-switch.db` 中 base URL 含 `opencode.ai/zen/go` 的所有 provider（Codex / Claude / OpenCode 等类型均可），有几个就显示几个。
- **Codex CLI**：Keychain `Codex Auth`，或 `$CODEX_HOME`/`~/.codex/auth.json`。
- **OpenCode**：`~/.local/share/opencode/auth.json` 中的 `opencode-go`。
- **Devin Desktop / Windsurf**：`state.vscdb` 中的 `windsurf_auth.sessions`，用 Keychain「Devin Safe Storage」解密（首次会弹出 Keychain 授权，选「始终允许」）。

## 手动添加更多账号

点「配置」打开 `~/.config/streamlet/config.json`：

```json
{
  "refreshMinutes": 5,
  "codex":      [{ "name": "工作号", "codexHome": "~/.codex-work" }],
  "opencodeGo": [{ "name": "Go 4", "apiKey": "sk-..." }],
  "devin":      [{ "name": "备用", "token": "devin-session-token$..." }]
}
```

`discoverCCSwitch` / `discoverCodexCLI` / `discoverOpenCodeAuth` / `discoverDevinDesktop` 设为 `false` 可关闭对应的自动发现。

## 构建

```bash
./build.sh                     # → build/Streamlet.app 和 build/Streamlet.zip（通用二进制，ad-hoc 签名）
swift run Streamlet --selftest # 离线解析/解密自检
swift run Streamlet --demo     # 演示数据
```

未公证的 app 首次打开：右键 →「打开」，或 `xattr -dr com.apple.quarantine Streamlet.app`。
