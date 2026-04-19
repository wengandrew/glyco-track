import CoreData
import Foundation

final class PersistenceController {
    static let shared = PersistenceController()

    let container: NSPersistentContainer

    private init(inMemory: Bool = false) {
        container = NSPersistentContainer(name: "GlycoTrack",
                                           managedObjectModel: .glycoTrackModel())
        if inMemory {
            container.persistentStoreDescriptions.first?.url = URL(fileURLWithPath: "/dev/null")
        }
        container.loadPersistentStores { _, error in
            if let error {
                fatalError("Core Data failed to load: \(error)")
            }
        }
        container.viewContext.automaticallyMergesChangesFromParent = true
        seedDatabaseIfNeeded()
    }

    var context: NSManagedObjectContext { container.viewContext }

    private func seedDatabaseIfNeeded() {
        let request = NutritionalProfile.fetchRequest()
        request.fetchLimit = 1
        let count = (try? context.count(for: request)) ?? 0
        guard count == 0 else { return }

        Task.detached(priority: .background) {
            await self.seedNutritionalProfiles()
        }
    }

    private func seedNutritionalProfiles() async {
        let bgContext = container.newBackgroundContext()

        guard
            let giURL = Bundle.main.url(forResource: "gi_database", withExtension: "json"),
            let usdaURL = Bundle.main.url(forResource: "usda_nutrition", withExtension: "json"),
            let giData = try? Data(contentsOf: giURL),
            let usdaData = try? Data(contentsOf: usdaURL),
            let giEntries = try? JSONDecoder().decode([GIEntry].self, from: giData),
            let usdaEntries = try? JSONDecoder().decode([USDAEntry].self, from: usdaData)
        else { return }

        let usdaMap = Dictionary(usdaEntries.map { ($0.name.lowercased(), $0) }, uniquingKeysWith: { a, _ in a })

        bgContext.performAndWait {
            for gi in giEntries {
                let profile = NutritionalProfile(context: bgContext)
                profile.id = UUID()
                profile.foodName = gi.name
                profile.glycemicIndex = Int16(gi.gi)
                profile.giSource = "Sydney GI Database"
                profile.nutritionSource = "USDA FoodData Central"

                let usda = usdaMap[gi.name.lowercased()]
                profile.carbsPer100g = usda?.carbs ?? 0
                profile.saturatedFatPer100g = usda?.sfa ?? 0
                profile.transFatPer100g = usda?.tfa ?? 0
                profile.solubleFiberPer100g = usda?.fiber ?? 0
                profile.pufaPer100g = usda?.pufa ?? 0
                profile.mufaPer100g = usda?.mufa ?? 0
            }

            // Seed USDA-only entries (no GI data)
            let giNames = Set(giEntries.map { $0.name.lowercased() })
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
            }

            try? bgContext.save()
        }
    }
}

// MARK: - Seed data models
private struct GIEntry: Decodable {
    let name: String
    let gi: Int
    let aliases: [String]
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
