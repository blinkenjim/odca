import Foundation

/// Display geometry shared by the viewers (R-U2, R-X8).
public enum Geometry {
    /// `--longest` (R-X8): the grid stretched to the window's width with its
    /// aspect kept. `factor` scales the cell (on screen it is `cell × factor`
    /// points), and `rows` is how many such rows fit the height (at least one).
    public static func fitToWidth(width: Double, height: Double, cols: Int, cell: Int) -> (factor: Double, rows: Int) {
        let factor = width / Double(cols * cell)
        return (factor, max(1, Int(height / (Double(cell) * factor))))
    }

    /// Whether a scale factor is a whole number: nearest-neighbor scaling
    /// then keeps every cell the same size; otherwise linear filtering
    /// avoids uneven cells (R-X8).
    public static func isWhole(_ factor: Double) -> Bool {
        abs(factor - factor.rounded()) < 1e-9
    }
}
