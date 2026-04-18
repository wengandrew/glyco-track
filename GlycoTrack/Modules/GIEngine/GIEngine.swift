import Foundation

// iOS app target wrapper — mirrors GIEngineCore SPM module.
// Keeps the same API so FoodLogProcessor can use it directly.

struct GIRecord: Codable {
    let name: String
    let gi: Int
    let aliases: [String]
}

struct GIDatabase {
    private let records: [GIRecord]
    private let nameIndex: [String: GIRecord]

    init(records: [GIRecord]) {
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

    func lookup(_ foodName: String) -> (record: GIRecord, confidence: Float, tier: Int)? {
        let normalized = foodName.lowercased().trimmingCharacters(in: .whitespaces)

        if let record = nameIndex[normalized] { return (record, 0.95, 1) }

        if let record = records.first(where: { rec in
            normalized.contains(rec.name.lowercased()) || rec.name.lowercased().contains(normalized)
            || rec.aliases.contains(where: { normalized.contains($0.lowercased()) || $0.lowercased().contains(normalized) })
        }) { return (record, 0.87, 1) }

        var bestRecord: GIRecord?
        var bestDistance = Int.max
        for record in records {
            let candidates = [record.name] + record.aliases
            for candidate in candidates {
                let d = levenshtein(normalized, candidate.lowercased())
                if d < bestDistance { bestDistance = d; bestRecord = record }
            }
        }
        if bestDistance <= 3, let record = bestRecord {
            let confidence: Float = bestDistance == 1 ? 0.80 : bestDistance == 2 ? 0.70 : 0.55
            return (record, confidence, 2)
        }
        return nil
    }

    private func levenshtein(_ a: String, _ b: String) -> Int {
        let aArr = Array(a), bArr = Array(b)
        let m = aArr.count, n = bArr.count
        guard m > 0 else { return n }; guard n > 0 else { return m }
        var dp = Array(repeating: Array(repeating: 0, count: n + 1), count: m + 1)
        for i in 0...m { dp[i][0] = i }
        for j in 0...n { dp[0][j] = j }
        for i in 1...m { for j in 1...n {
            dp[i][j] = aArr[i-1] == bArr[j-1] ? dp[i-1][j-1] : 1 + min(dp[i-1][j], dp[i][j-1], dp[i-1][j-1])
        }}
        return dp[m][n]
    }
}

struct GLResult {
    let gl: Double
    let gi: Int
    let carbs: Double
    let confidence: Float
    let tier: Int
    let matchedFoodName: String?
}

let dailyGLBudget: Double = 100.0

final class GIEngine {
    private let database: GIDatabase

    init(database: GIDatabase) {
        self.database = database
    }

    func computeGL(foodName: String, quantityGrams: Double, carbsPer100g: Double) -> GLResult {
        let carbsInServing = carbsPer100g * quantityGrams / 100.0

        guard let match = database.lookup(foodName) else {
            let gl = (55.0 * carbsInServing) / 100.0
            return GLResult(gl: max(0, gl), gi: 55, carbs: carbsInServing, confidence: 0.35, tier: 3, matchedFoodName: nil)
        }

        let gi = Double(match.record.gi)
        let gl = (gi * carbsInServing) / 100.0
        return GLResult(gl: max(0, gl), gi: match.record.gi, carbs: carbsInServing,
                        confidence: match.confidence, tier: match.tier, matchedFoodName: match.record.name)
    }

    static func computeGL(gi: Int, carbsGrams: Double) -> Double {
        max(0, (Double(gi) * carbsGrams) / 100.0)
    }
}
