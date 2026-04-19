import CoreData

// Builds the NSManagedObjectModel in code so the project has no .xcdatamodeld
// file. Xcode 26's CDMFoundation indexer crashes on any .xcdatamodel file
// processed by IDEDataModelTextFragmentProvider; removing the file eliminates
// the crash entirely.
extension NSManagedObjectModel {
    static func glycoTrackModel() -> NSManagedObjectModel {
        let model = NSManagedObjectModel()

        // MARK: FoodLogEntry
        let foodLogEntry = NSEntityDescription()
        foodLogEntry.name = "FoodLogEntry"
        foodLogEntry.managedObjectClassName = NSStringFromClass(FoodLogEntry.self)

        let fle: [NSAttributeDescription] = [
            attr("computedCL",      .doubleAttributeType,    0.0,              false),
            attr("computedGL",      .doubleAttributeType,    0.0,              false),
            attr("confidenceScore", .floatAttributeType,     Float(0),         false),
            attr("foodDescription", .stringAttributeType,    "",               false),
            attr("foodGroup",       .stringAttributeType,    "proteins",       false),
            attr("id",              .UUIDAttributeType,      nil,              true),
            attr("isEdited",        .booleanAttributeType,   false,            false),
            attr("isSoftDeleted",   .booleanAttributeType,   false,            false),
            attr("loggedAt",        .dateAttributeType,      nil,              true),
            attr("parsingMethod",   .integer16AttributeType, Int16(1),         false),
            attr("quantity",        .stringAttributeType,    "1",              false),
            attr("quantityGrams",   .doubleAttributeType,    100.0,            false),
            attr("rawTranscript",   .stringAttributeType,    "",               false),
            attr("referenceFood",   .stringAttributeType,    nil,              true),
            attr("timestamp",       .dateAttributeType,      nil,              true),
        ]

        // MARK: NutritionalProfile
        let nutritionalProfile = NSEntityDescription()
        nutritionalProfile.name = "NutritionalProfile"
        nutritionalProfile.managedObjectClassName = NSStringFromClass(NutritionalProfile.self)

        let np: [NSAttributeDescription] = [
            attr("carbsPer100g",          .doubleAttributeType,    0.0, false),
            attr("foodName",              .stringAttributeType,    "",  false),
            attr("giSource",              .stringAttributeType,    "",  false),
            attr("glycemicIndex",         .integer16AttributeType, Int16(0), false),
            attr("id",                    .UUIDAttributeType,      nil, true),
            attr("mufaPer100g",           .doubleAttributeType,    0.0, false),
            attr("nutritionSource",       .stringAttributeType,    "",  false),
            attr("pufaPer100g",           .doubleAttributeType,    0.0, false),
            attr("saturatedFatPer100g",   .doubleAttributeType,    0.0, false),
            attr("solubleFiberPer100g",   .doubleAttributeType,    0.0, false),
            attr("transFatPer100g",       .doubleAttributeType,    0.0, false),
        ]

        // MARK: Relationships
        let fleToNP = NSRelationshipDescription()
        fleToNP.name = "nutritionalProfile"
        fleToNP.destinationEntity = nutritionalProfile
        fleToNP.isOptional = true
        fleToNP.minCount = 0
        fleToNP.maxCount = 1
        fleToNP.deleteRule = .nullifyDeleteRule

        let npToFLE = NSRelationshipDescription()
        npToFLE.name = "foodLogEntries"
        npToFLE.destinationEntity = foodLogEntry
        npToFLE.isOptional = true
        npToFLE.minCount = 0
        npToFLE.maxCount = 0 // to-many
        npToFLE.deleteRule = .nullifyDeleteRule

        fleToNP.inverseRelationship = npToFLE
        npToFLE.inverseRelationship = fleToNP

        foodLogEntry.properties = fle + [fleToNP]
        nutritionalProfile.properties = np + [npToFLE]
        model.entities = [foodLogEntry, nutritionalProfile]
        return model
    }

    private static func attr(
        _ name: String,
        _ type: NSAttributeType,
        _ defaultValue: Any?,
        _ optional: Bool
    ) -> NSAttributeDescription {
        let d = NSAttributeDescription()
        d.name = name
        d.attributeType = type
        d.defaultValue = defaultValue
        d.isOptional = optional
        return d
    }
}
