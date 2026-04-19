import Foundation
import CoreData

extension NutritionalProfile {
    @nonobjc public class func fetchRequest() -> NSFetchRequest<NutritionalProfile> {
        return NSFetchRequest<NutritionalProfile>(entityName: "NutritionalProfile")
    }

    @NSManaged public var carbsPer100g: Double
    @NSManaged public var foodName: String
    @NSManaged public var giSource: String
    @NSManaged public var glycemicIndex: Int16
    @NSManaged public var id: UUID?
    @NSManaged public var mufaPer100g: Double
    @NSManaged public var nutritionSource: String
    @NSManaged public var pufaPer100g: Double
    @NSManaged public var saturatedFatPer100g: Double
    @NSManaged public var solubleFiberPer100g: Double
    @NSManaged public var transFatPer100g: Double
    @NSManaged public var foodLogEntries: NSSet?
}

extension NutritionalProfile: Identifiable {}
