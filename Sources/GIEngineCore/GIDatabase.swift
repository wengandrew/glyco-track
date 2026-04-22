import Foundation

public struct GIRecord: Codable {
    public let name: String
    public let gi: Int
    public let aliases: [String]
}

public struct GIDatabase {
    private let records: [GIRecord]
    private let nameIndex: [String: GIRecord]

    public init(records: [GIRecord]) {
        self.records = records
        var index: [String: GIRecord] = [:]
        for record in records {
            index[record.name.lowercased()] = record
            for alias in record.aliases {
                index[alias.lowercased()] = record
            }
        }
        self.nameIndex = index
    }

    public func lookup(_ foodName: String) -> (record: GIRecord, confidence: Float, tier: Int)? {
        let normalized = foodName.lowercased().trimmingCharacters(in: .whitespaces)

        // Tier 1: exact match on canonical name or alias.
        if let record = nameIndex[normalized] {
            return (record, 0.95, 1)
        }

        // NOTE: bidirectional substring matching was removed. Composite names
        // like "beef noodle soup" used to spuriously match any short DB token
        // inside them (e.g. "beef"), reporting ~0.87 confidence while the
        // caller's macro lookup returned nothing. Use the cascade in
        // FoodMatcher (iOS layer) for composite-name decomposition.

        // Tier 2: fuzzy match (Levenshtein ≤ 3) — typos only.
        var bestRecord: GIRecord?
        var bestDistance = Int.max
        for record in records {
            let candidates = [record.name] + record.aliases
            for candidate in candidates {
                let d = levenshtein(normalized, candidate.lowercased())
                if d < bestDistance {
                    bestDistance = d
                    bestRecord = record
                }
            }
        }
        if bestDistance <= 3, let record = bestRecord {
            let confidence: Float = bestDistance == 1 ? 0.80 : bestDistance == 2 ? 0.70 : 0.55
            return (record, confidence, 2)
        }

        return nil
    }

    private func levenshtein(_ a: String, _ b: String) -> Int {
        let aArr = Array(a)
        let bArr = Array(b)
        let m = aArr.count, n = bArr.count
        guard m > 0 else { return n }
        guard n > 0 else { return m }
        var dp = Array(repeating: Array(repeating: 0, count: n + 1), count: m + 1)
        for i in 0...m { dp[i][0] = i }
        for j in 0...n { dp[0][j] = j }
        for i in 1...m {
            for j in 1...n {
                dp[i][j] = aArr[i-1] == bArr[j-1]
                    ? dp[i-1][j-1]
                    : 1 + min(dp[i-1][j], dp[i][j-1], dp[i-1][j-1])
            }
        }
        return dp[m][n]
    }
}
