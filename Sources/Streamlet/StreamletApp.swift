import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }
}

struct StreamletApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject private var store = UsageStore()

    var body: some Scene {
        MenuBarExtra {
            PopoverView(store: store)
        } label: {
            Image(nsImage: StreamIcon.image(size: 18, template: true))
        }
        .menuBarExtraStyle(.window)
    }
}

@main
enum Main {
    static func main() {
        let args = CommandLine.arguments
        if args.contains("--selftest") { exit(SelfTest.run()) }
        if let i = args.firstIndex(of: "--render-icon"), args.count > i + 2,
           let px = Int(args[i + 2]), let png = StreamIcon.appIconPNG(pixels: px) {
            try? png.write(to: URL(fileURLWithPath: args[i + 1])); exit(0)
        }
        if let i = args.firstIndex(of: "--snapshot"), args.count > i + 1 {
            MainActor.assumeIsolated { Snapshot.run(path: args[i + 1]) }
            exit(0)
        }
        StreamletApp.main()
    }
}
