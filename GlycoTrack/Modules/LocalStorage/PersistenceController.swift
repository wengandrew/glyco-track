import CoreData
import Foundation
import os

final class PersistenceController {
    static let shared = PersistenceController()

    let container: NSPersistentContainer

    /// `inMemory: true` is for tests — skips the persistent store on disk and
    /// the auto-seed background task so callers can `await seedNutritionalProfiles()`
    /// synchronously. Internal-not-private so test targets can reach it.
    init(inMemory: Bool = false) {
        container = NSPersistentContainer(name: "GlycoTrack",
                                           managedObjectModel: .glycoTrackModel())
        if inMemory {
            container.persistentStoreDescriptions.first?.url = URL(fileURLWithPath: "/dev/null")
        }
        container.loadPersistentStores { _, error in
            if let error {
                // .fault so a Console.app filter on this category surfaces the
                // failure even after the crash dialog dismisses. The crash
                // itself is non-negotiable — without the persistent store,
                // every Core Data op above this layer would otherwise fail
                // silently in unpredictable ways.
                Log.coreData.fault("Core Data failed to load: \(error.localizedDescription, privacy: .public)")
                fatalError("Core Data failed to load: \(error)")
            }
        }
        container.viewContext.automaticallyMergesChangesFromParent = true
        if !inMemory {
            seedDatabaseIfNeeded()
        }
    }

    var context: NSManagedObjectContext { container.viewContext }

    /// True if a first-launch seed was started. Set synchronously before the
    /// background task is spawned so `GlycoTrackApp` can read it in `.onAppear`
    /// without racing against the `glycoTrackSeedingDidComplete` notification.
    private(set) var isSeedingOnFirstLaunch = false

    private func seedDatabaseIfNeeded() {
        let request = NutritionalProfile.fetchRequest()
        request.fetchLimit = 1
        let count = (try? context.count(for: request)) ?? 0
        guard count == 0 else { return }

        isSeedingOnFirstLaunch = true
        Task.detached(priority: .background) {
            await self.seedNutritionalProfiles()
            await MainActor.run {
                NotificationCenter.default.post(name: .glycoTrackSeedingDidComplete, object: nil)
            }
        }
    }

    /// Number of profiles to insert per save. Saving in batches (and resetting
    /// the context between batches) keeps the row-buffer the bg context holds
    /// bounded — at full ~7,793-USDA scale a single save was projected to peak
    /// well into hundreds of MB. At the current ~1,150 rows it's overkill but
    /// cheap, and forward-compatible with the planned USDA expansion (PLAN A.1).
    private static let seedBatchSize = 500

    /// Internal so test targets can `await` it after an in-memory init.
    func seedNutritionalProfiles() async {
        let signpost = OSSignposter(subsystem: "com.glycotrack.app", category: "coreData")
        let overall = signpost.beginInterval("seed", id: signpost.makeSignpostID())

        let loadStart = Date()
        guard
            let giURL = Bundle.main.url(forResource: "gi_database", withExtension: "json"),
            let usdaURL = Bundle.main.url(forResource: "usda_nutrition", withExtension: "json"),
            let giData = try? Data(contentsOf: giURL),
            let usdaData = try? Data(contentsOf: usdaURL),
            let giEntries = try? JSONDecoder().decode([GIEntry].self, from: giData),
            let usdaEntries = try? JSONDecoder().decode([USDAEntry].self, from: usdaData)
        else {
            signpost.endInterval("seed", overall)
            Log.coreData.error("Seed bailed: missing or unreadable JSON resources")
            return
        }
        let loadMs = Date().timeIntervalSince(loadStart) * 1000

        let usdaMap = Dictionary(usdaEntries.map { ($0.name.lowercased(), $0) }, uniquingKeysWith: { a, _ in a })
        let giNames = Set(giEntries.map { $0.name.lowercased() })

        let bgContext = container.newBackgroundContext()
        // Avoid undo-stack growth under bulk inserts. We never undo the seed.
        bgContext.undoManager = nil

        let insertStart = Date()
        var inserted = 0

        bgContext.performAndWait {
            for gi in giEntries {
                let profile = NutritionalProfile(context: bgContext)
                profile.id = UUID()
                profile.foodName = gi.name
                profile.glycemicIndex = Int16(gi.gi)
                profile.giSource = "Sydney GI Database"
                profile.nutritionSource = "USDA FoodData Central"

                let usda = usdaMap[gi.name.lowercased()]
                profile.carbsPer100g = usda?.carbs ?? gi.carbs ?? 0
                profile.saturatedFatPer100g = usda?.sfa ?? 0
                profile.transFatPer100g = usda?.tfa ?? 0
                profile.solubleFiberPer100g = usda?.fiber ?? 0
                profile.pufaPer100g = usda?.pufa ?? 0
                profile.mufaPer100g = usda?.mufa ?? 0

                inserted += 1
                if inserted % Self.seedBatchSize == 0 {
                    Self.flushSeedBatch(bgContext)
                }
            }

            // Seed USDA-only entries (no GI data)
            for usda in usdaEntries where !giNames.contains(usda.name.lowercased()) {
                let profile = NutritionalProfile(context: bgContext)
                profile.id = UUID()
                profile.foodName = usda.name
                profile.glycemicIndex = 0
                profile.giSource = ""
                profile.nutritionSource = "USDA FoodData Central"
                profile.carbsPer100g = usda.carbs
                profile.saturatedFatPer100g = usda.sfa
                profile.transFatPer100g = usda.tfa
                profile.solubleFiberPer100g = usda.fiber
                profile.pufaPer100g = usda.pufa
                profile.mufaPer100g = usda.mufa

                inserted += 1
                if inserted % Self.seedBatchSize == 0 {
                    Self.flushSeedBatch(bgContext)
                }
            }

            // Final partial batch.
            Self.flushSeedBatch(bgContext)
        }

        let insertMs = Date().timeIntervalSince(insertStart) * 1000
        signpost.endInterval("seed", overall)
        Log.coreData.info("""
            Seed complete: \(inserted, privacy: .public) profiles, \
            load=\(loadMs, format: .fixed(precision: 1), privacy: .public)ms, \
            insert=\(insertMs, format: .fixed(precision: 1), privacy: .public)ms
            """)
    }

    /// Save the bg context and reset it. Resetting drops the row buffer Core
    /// Data accumulates as objects are inserted, keeping memory bounded across
    /// the full seed. Cheap because we never reference the inserted objects
    /// after this returns — the seed is fire-and-forget.
    private static func flushSeedBatch(_ context: NSManagedObjectContext) {
        guard context.hasChanges else { return }
        do {
            try context.save()
            context.reset()
        } catch {
            Log.coreData.error("Seed batch save failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}

// MARK: - Notifications

extension Notification.Name {
    static let glycoTrackSeedingDidComplete = Notification.Name("com.glycotrack.seedingDidComplete")
}

// MARK: - Seed data models
private struct GIEntry: Decodable {
    let name: String
    let gi: Int
    let aliases: [String]
    let carbs: Double?
}

private struct USDAEntry: Decodable {
    let name: String
    let carbs: Double
    let sfa: Double
    let tfa: Double
    let fiber: Double
    let pufa: Double
    let mufa: Double
}
