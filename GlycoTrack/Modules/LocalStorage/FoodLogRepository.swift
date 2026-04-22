import CoreData
import Foundation

@MainActor
final class FoodLogRepository {
    private let context: NSManagedObjectContext

    init(context: NSManagedObjectContext = PersistenceController.shared.context) {
        self.context = context
    }

    func create(
        rawTranscript: String,
        foodDescription: String,
        quantity: String,
        quantityGrams: Double,
        timestamp: Date,
        confidenceScore: Float,
        parsingMethod: Int16,
        referenceFood: String?,
        foodGroup: String,
        computedGL: Double,
        computedCL: Double,
        nutritionalProfile: NutritionalProfile?
    ) -> FoodLogEntry {
        let entry = FoodLogEntry(context: context)
        entry.id = UUID()
        entry.rawTranscript = rawTranscript
        entry.foodDescription = foodDescription
        entry.quantity = quantity
        entry.quantityGrams = quantityGrams
        entry.timestamp = timestamp
        entry.loggedAt = Date()
        entry.confidenceScore = confidenceScore
        entry.parsingMethod = parsingMethod
        entry.referenceFood = referenceFood
        entry.foodGroup = foodGroup
        entry.computedGL = computedGL
        entry.computedCL = computedCL
        entry.isEdited = false
        entry.isSoftDeleted = false
        entry.nutritionalProfile = nutritionalProfile
        save()
        return entry
    }

    func update(_ entry: FoodLogEntry,
                foodDescription: String,
                quantity: String,
                quantityGrams: Double,
                computedGL: Double,
                computedCL: Double,
                confidenceScore: Float? = nil,
                parsingMethod: Int16? = nil,
                referenceFood: String?? = nil,
                nutritionalProfile: NutritionalProfile?? = nil) {
        entry.foodDescription = foodDescription
        entry.quantity = quantity
        entry.quantityGrams = quantityGrams
        entry.computedGL = computedGL
        entry.computedCL = computedCL
        if let confidenceScore { entry.confidenceScore = confidenceScore }
        if let parsingMethod { entry.parsingMethod = parsingMethod }
        if let referenceFood { entry.referenceFood = referenceFood }
        if let nutritionalProfile { entry.nutritionalProfile = nutritionalProfile }
        entry.isEdited = true
        save()
    }

    func softDelete(_ entry: FoodLogEntry) {
        entry.isSoftDeleted = true
        save()
    }

    func fetchToday() -> [FoodLogEntry] {
        fetch(from: Calendar.current.startOfDay(for: Date()), to: Date())
    }

    func fetch(from start: Date, to end: Date) -> [FoodLogEntry] {
        let request = FoodLogEntry.fetchRequest()
        request.predicate = NSPredicate(
            format: "timestamp >= %@ AND timestamp <= %@ AND isSoftDeleted == NO",
            start as NSDate,
            end as NSDate
        )
        request.sortDescriptors = [NSSortDescriptor(key: "timestamp", ascending: false)]
        return (try? context.fetch(request)) ?? []
    }

    func fetchAll() -> [FoodLogEntry] {
        let request = FoodLogEntry.fetchRequest()
        request.predicate = NSPredicate(format: "isSoftDeleted == NO")
        request.sortDescriptors = [NSSortDescriptor(key: "timestamp", ascending: false)]
        return (try? context.fetch(request)) ?? []
    }

    func countToday() -> Int {
        let start = Calendar.current.startOfDay(for: Date())
        let request = FoodLogEntry.fetchRequest()
        request.predicate = NSPredicate(
            format: "timestamp >= %@ AND isSoftDeleted == NO",
            start as NSDate
        )
        return (try? context.count(for: request)) ?? 0
    }

    func dailyGL(for date: Date) -> Double {
        fetch(for: date).reduce(0) { $0 + $1.computedGL }
    }

    func dailyCL(for date: Date) -> Double {
        fetch(for: date).reduce(0) { $0 + $1.computedCL }
    }

    private func fetch(for date: Date) -> [FoodLogEntry] {
        let cal = Calendar.current
        let start = cal.startOfDay(for: date)
        let end = cal.date(byAdding: .day, value: 1, to: start)!
        return fetch(from: start, to: end)
    }

    private func save() {
        guard context.hasChanges else { return }
        try? context.save()
    }
}
