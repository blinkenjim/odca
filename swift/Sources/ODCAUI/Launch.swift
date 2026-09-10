import AppKit
import ODCAKit

/// Open the window on a session built by `make` (called once, on the main
/// actor, with the default geometry) and run the app until it quits.
/// `fullScreen` opens the window full screen at launch (`--fullscreen`, R-U2);
/// `cellSize` is the points per cell for the run (`--4` / `--3` / `--2` / `--1`).
@MainActor
public func launch(fullScreen: Bool = false, cellSize: Int = 2, cols: Int? = nil,
                   _ make: @escaping (_ cols: Int, _ rows: Int) -> Session) {
    ViewerModel.cellSize = cellSize
    ViewerModel.fixedCols = cols  // `--longest` (R-X8): the window is as wide as the seeds
    ViewerModel.bootstrap { make(ViewerModel.defaultCols, ViewerModel.defaultRows) }
    AppDelegate.fullScreenAtLaunch = fullScreen
    // AppKit treats unknown command-line arguments as documents to open, and
    // SwiftUI then shows no default window (it expects a DocumentGroup to
    // take the file). Our argument is ours, not a document (3.0.0 shipped
    // without this and opened no window).
    UserDefaults.standard.register(defaults: ["NSTreatUnknownArgumentsAsOpen": "NO"])
    ODCAApp.main()
}
