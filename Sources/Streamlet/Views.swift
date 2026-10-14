import AppKit
import SwiftUI

struct PopoverView: View {
    @ObservedObject var store: UsageStore
    var snapshot = false
    @State private var contentHeight: CGFloat = 300

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(nsImage: StreamIcon.image(size: 18, template: false))
                Text("Streamlet · 订阅用量").font(.headline)
                Spacer()
                if store.loading { ProgressView().controlSize(.small) }
                Button { Task { await store.refresh() } } label: { Image(systemName: "arrow.clockwise") }
                    .buttonStyle(.plain).help("刷新").disabled(store.loading)
            }

            scroll {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(ProviderKind.allCases, id: \.self) { kind in
                        let list = store.accounts.filter { $0.kind == kind }
                        if !list.isEmpty {
                            Text(kind.title).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                            ForEach(list) { AccountCard(account: $0) }
                        }
                    }
                    if store.accounts.isEmpty && !store.loading {
                        Text("没有发现账号。请在 cc-switch / Codex CLI / Devin Desktop 中登录，或点「配置」手动添加。")
                            .font(.callout).foregroundStyle(.secondary).padding(.vertical, 20)
                    }
                    ForEach(store.problems, id: \.self) { p in
                        Label(p, systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.orange)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Divider()
            HStack {
                if let t = store.lastUpdated {
                    Text("更新于 \(t.formatted(date: .omitted, time: .shortened))").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button { store.setLaunchAtLogin(!store.launchAtLogin) } label: {
                    Label("开机启动", systemImage: store.launchAtLogin ? "checkmark.square.fill" : "square")
                }
                .buttonStyle(.plain).font(.caption)
                Button("配置") { store.openConfig() }.buttonStyle(.plain).font(.caption).foregroundStyle(Color.accentColor)
                Button("退出") { NSApp.terminate(nil) }.buttonStyle(.plain).font(.caption).foregroundStyle(Color.accentColor)
            }
        }
        .padding(12)
        .frame(width: 380)
        .onAppear { if !snapshot { store.refreshIfStale() } }
    }

    @ViewBuilder func scroll<C: View>(@ViewBuilder _ content: () -> C) -> some View {
        if snapshot { content() } else {
            ScrollView {
                content().background(GeometryReader { g in
                    Color.clear.preference(key: ContentHeightKey.self, value: g.size.height)
                })
            }
            .frame(height: min(max(contentHeight, 60), 560))
            .onPreferenceChange(ContentHeightKey.self) { contentHeight = $0 }
        }
    }
}

private struct ContentHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

/// `--snapshot out.png [--demo]`: refresh once and render the popover to PNG.
enum Snapshot {
    @MainActor static func run(path: String) {
        let store = UsageStore()
        let deadline = Date().addingTimeInterval(60)
        while (store.lastUpdated == nil || store.loading) && Date() < deadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        }
        let view = PopoverView(store: store, snapshot: true).background(Color(nsColor: .windowBackgroundColor))
        let r = ImageRenderer(content: view)
        r.scale = 2
        if let img = r.nsImage, let tiff = img.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
           let png = rep.representation(using: .png, properties: [:]) {
            try? png.write(to: URL(fileURLWithPath: path))
        }
    }
}

struct AccountCard: View {
    let account: AccountUsage

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text(account.name).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                if let b = account.badge, !b.isEmpty {
                    Text(b).font(.caption2).padding(.horizontal, 6).padding(.vertical, 1)
                        .overlay(Capsule().stroke(Color.secondary.opacity(0.5)))
                }
                Spacer()
            }
            if let s = account.subtitle, !s.isEmpty {
                Text(s).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
            }
            if let e = account.error {
                Text(e).font(.caption).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
            }
            ForEach(account.windows) { WindowRow(window: $0) }
            if !account.notes.isEmpty {
                Text(account.notes.joined(separator: " · ")).font(.caption2).foregroundStyle(.secondary)
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color(nsColor: .controlBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.secondary.opacity(0.2)))
    }
}

struct WindowRow: View {
    let window: UsageWindow

    var color: Color {
        switch window.remainingPercent {
        case ..<10: return .red
        case ..<30: return .orange
        default: return Color(red: 0.16, green: 0.62, blue: 0.85)
        }
    }

    var body: some View {
        HStack(spacing: 8) {
            Text(window.label).font(.caption).frame(width: 44, alignment: .leading)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.secondary.opacity(0.18))
                    Capsule().fill(color).frame(width: max(0, geo.size.width * window.remainingPercent / 100))
                }
            }
            .frame(height: 6)
            Text("\(Int(window.remainingPercent.rounded()))%")
                .font(.caption.monospacedDigit()).foregroundStyle(window.remainingPercent < 10 ? .red : .primary)
                .frame(width: 38, alignment: .trailing)
            Group {
                if let r = window.resetAt {
                    Label(formatCountdown(r), systemImage: "clock").labelStyle(.titleAndIcon)
                } else {
                    Text(" ")
                }
            }
            .font(.caption2.monospacedDigit()).foregroundStyle(.secondary).frame(width: 64, alignment: .leading)
        }
        .help("剩余 \(Int(window.remainingPercent.rounded()))%" + (window.resetAt.map { "，\($0.formatted()) 重置" } ?? ""))
    }
}
