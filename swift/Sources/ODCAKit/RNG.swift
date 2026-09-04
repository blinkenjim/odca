/// Seedable PRNG (R-N1): xoshiro256** seeded through SplitMix64.
/// The no-argument initializer seeds from OS entropy so independent
/// instances (e.g. per search worker) get distinct streams.
public struct Xoshiro256: RandomNumberGenerator {
    private var s0: UInt64, s1: UInt64, s2: UInt64, s3: UInt64

    public init(seed: UInt64) {
        var sm = seed
        func splitmix() -> UInt64 {
            sm &+= 0x9E37_79B9_7F4A_7C15
            var z = sm
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            return z ^ (z >> 31)
        }
        s0 = splitmix(); s1 = splitmix(); s2 = splitmix(); s3 = splitmix()
    }

    public init() {
        var system = SystemRandomNumberGenerator()
        self.init(seed: system.next())
    }

    public mutating func next() -> UInt64 {
        func rotl(_ x: UInt64, _ k: UInt64) -> UInt64 { (x << k) | (x >> (64 - k)) }
        let result = rotl(s1 &* 5, 7) &* 9
        let t = s1 << 17
        s2 ^= s0
        s3 ^= s1
        s1 ^= s2
        s0 ^= s3
        s2 ^= t
        s3 = rotl(s3, 45)
        return result
    }
}
