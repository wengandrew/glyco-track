import Foundation
import CoreData

extension FoodLogEntry {
    @nonobjc public class func fetchRequest() -> NSFetchRequest<FoodLogEntry> {
        return NSFetchRequest<FoodLogEntry>(entityName: "FoodLogEntry")
    }

    @NSManaged public var computedCL: Double
    @NSManaged public var computedGL: Double
    @NSManaged public var confidenceScore: Float
    @NSManaged public var foodDescription: String
    @NSManaged public var foodGroup: String
    @NSManaged public var id: UUID?
    @NSManaged public var isSoftDeleted: Bool
    @NSManaged public var isEdited: Bool
    @NSManaged public var loggedAt: Date?
    @NSManaged public var parsingMethod: Int16
    @NSManaged public var quantity: String
    @NSManaged public var quantityGrams: Double
    @NSManaged public var rawTranscript: String
    @NSManaged public var referenceFood: String?
    @NSManaged public var timestamp: Date?
    @NSManaged public var nutritionalProfile: NutritionalProfile?
}

extension FoodLogEntry: Identifiable {}
