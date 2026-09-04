import Foundation

/// Maybe-Class-IV behavioral screening (R-C1..R-C6).

public struct ScreeningResult {
    public let maybeIV: Bool
    public let reason: String
    public let score: Double
    public let meanEntropy: Double
    public let stdEntropy: Double
    public let cyclePeriod: Int?
}

public enum Classifier {
    public static let width = 256
    public static let transient = 200
    public static let sample = 400

    // Thresholds per R-C4 (calibrated on random rules, see R-C5).
    public static let chaosMean = 0.80
    public static let flatStd = 0.02
    public static let candidateStd = 0.055

    static let maxEntropy = log2(20.0)

    public static func evaluate(
        _ rule: Rule, using rng: inout some RandomNumberGenerator
    ) -> ScreeningResult {
        var automaton = try! Automaton(
            width: width, rule: rule,
            cells: Automaton.randomCells(width: width, using: &rng))
        for _ in 0..<transient { automaton.step() }

        var seen: [[UInt8]: Int] = [:]
        var entropies: [Double] = []
        var cyclePeriod: Int?
        for t in 0..<sample {
            if let previous = seen[automaton.cells] {
                cyclePeriod = t - previous
                break
            }
            seen[automaton.cells] = t
            var counts = [Int](repeating: 0, count: Rule.denseSize)
            for s in automaton.neighborhoodSums() { counts[Int(s)] += 1 }
            var entropy = 0.0
            for c in counts where c > 0 {
                let p = Double(c) / Double(width)
                entropy -= p * log2(p)
            }
            entropies.append(entropy / maxEntropy)
            automaton.step()
        }

        let mean = entropies.isEmpty
            ? 0 : entropies.reduce(0, +) / Double(entropies.count)
        if let period = cyclePeriod {
            return ScreeningResult(
                maybeIV: false, reason: "cyclic (period \(period))", score: 0,
                meanEntropy: mean, stdEntropy: 0, cyclePeriod: period)
        }
        // Population standard deviation, matching the reference implementation.
        let variance = entropies.reduce(0) { $0 + ($1 - mean) * ($1 - mean) }
            / Double(entropies.count)
        let std = variance.squareRoot()

        let maybeIV: Bool
        let reason: String
        if std >= candidateStd {
            maybeIV = true
            reason = "candidate"
        } else if mean > chaosMean && std < flatStd {
            maybeIV = false
            reason = "chaotic"
        } else {
            maybeIV = false
            reason = "flat"
        }
        return ScreeningResult(
            maybeIV: maybeIV, reason: reason, score: std,
            meanEntropy: mean, stdEntropy: std, cyclePeriod: nil)
    }

    /// Generate and screen random rules until one passes (R-C6). If
    /// maxTries all fail, returns the best-scoring rule seen — the caller
    /// always gets a rule.
    public static func findCandidate(
        using rng: inout some RandomNumberGenerator, maxTries: Int = 200
    ) -> (rule: Rule, tries: Int) {
        var best: Rule?
        var bestScore = -1.0
        for i in 1...maxTries {
            let rule = Rule.random(using: &rng)
            let result = evaluate(rule, using: &rng)
            if result.maybeIV { return (rule, i) }
            if result.score > bestScore {
                best = rule
                bestScore = result.score
            }
        }
        return (best!, maxTries)
    }
}
