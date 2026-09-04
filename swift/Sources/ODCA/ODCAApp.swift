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

struct ContentView: View {
    @ObservedObject var model: ViewerModel

    var body: some View {
        let cell = CGFloat(ViewerModel.cellSize)
        let width = CGFloat(ViewerModel.cols) * cell
        let height = CGFloat(ViewerModel.rows) * cell
        Group {
            if let frame = model.frame {
                // The image holds rows + 1 rows; slide it up by the scroll
                // offset (R-U3) inside a window-sized clip.
                Image(decorative: frame, scale: 1)
                    .resizable()
                    .interpolation(.none)  // crisp cells, no smoothing
                    .frame(width: width, height: height + cell)
                    .offset(y: -CGFloat(model.scrollOffset) * cell)
            } else {
                Color.black
            }
        }
        .frame(width: width, height: height, alignment: .top)
        .clipped()
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
