import SwiftUI
import ODCAKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Needed when launched via `swift run` (no app bundle): become a
        // regular, focusable app and take the foreground.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(
        _ sender: NSApplication
    ) -> Bool {
        true  // closing the window quits (R-U7)
    }

    func applicationWillTerminate(_ notification: Notification) {
        Task { @MainActor in ViewerModel.shared.shutDown() }
    }
}

/// Hosts the display-link-driven AutomatonView inside SwiftUI.
struct AutomatonViewRepresentable: NSViewRepresentable {
    let model: ViewerModel

    func makeNSView(context: Context) -> AutomatonView { AutomatonView(model: model) }
    func updateNSView(_ view: AutomatonView, context: Context) {}
}

struct ContentView: View {
    @ObservedObject var model: ViewerModel

    var body: some View {
        AutomatonViewRepresentable(model: model)
            .frame(
                width: CGFloat(ViewerModel.cols * ViewerModel.cellSize),
                height: CGFloat(ViewerModel.rows * ViewerModel.cellSize))
            .navigationTitle(model.title)
    }
}

@main
struct ODCAApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate

    var body: some Scene {
        WindowGroup {
            ContentView(model: ViewerModel.shared)
        }
        .windowResizability(.contentSize)
    }
}
