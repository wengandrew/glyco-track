import Foundation

/// In-memory index of GI-database aliases. The bundled `gi_database.json`
/// declares aliases on most entries — "grilled chicken"/"roasted chicken" on
/// `chicken breast`, "bread"/"toast" on `white bread`, "sugar" on `white
/// sugar`, etc. Those aliases were always present in the JSON but were
/// silently dropped during Core Data seeding (`PersistenceController.GIEntry`
/// decoded the field and never wrote it to NutritionalProfile), so the
/// matcher had no way to resolve a query like "grilled chicken" to the right
/// profile and would either fall through to a fuzzy bridge across prep
/// methods or to T5 unrecognized.
///
/// Storing aliases on the Core Data model would be a schema change (and a
/// migration for existing installs). Aliases are static reference data, so
/// keeping them in memory is cheaper, requires no migration, and re-loads
/// from the JSON on every cold launch.
final class AliasIndex {
    static let shared = AliasIndex()

    /// alias (lowercased, trimmed) → canonical foodName (original casing,
    /// suitable for an exact `foodName ==[cd]` fetch).
    private(set) var aliasToCanonical: [String: String] = [:]
    /// canonical foodName (lowercased) → [alias (lowercased, trimmed)].
    /// Used by component (T2) scanning so the matcher can find an alias
    /// substring inside a longer query — e.g. "grilled chicken caesar
    /// salad" surfacing the "grilled chicken" alias of `chicken breast`.
    private(set) var canonicalToAliases: [String: [String]] = [:]

    private init() { reload() }

    func reload() {
        aliasToCanonical = [:]
        canonicalToAliases = [:]

        guard
            let url = Bundle.main.url(forResource: "gi_database", withExtension: "json"),
            let data = try? Data(contentsOf: url),
            let entries = try? JSONDecoder().decode([Entry].self, from: data)
        else { return }

        for entry in entries {
            let canonicalLower = entry.name.lowercased()
            let normalizedAliases = entry.aliases
                .map { $0.lowercased().trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
            canonicalToAliases[canonicalLower] = normalizedAliases
            for alias in normalizedAliases {
                // First-wins on collisions. Two entries declaring the same
                // alias is a JSON-level data inconsistency (e.g. "tomato
                // sauce" appears on both `ketchup` and `marinara sauce`) —
                // picking deterministically beats picking randomly. Curating
                // the JSON to remove duplicate aliases is the long-term fix.
                if aliasToCanonical[alias] == nil {
                    aliasToCanonical[alias] = entry.name
                }
            }
        }
    }

    /// Canonical foodName when the query is an exact alias of some entry.
    /// nil if the query isn't a declared alias.
    func canonical(forAlias query: String) -> String? {
        let key = query.lowercased().trimmingCharacters(in: .whitespaces)
        return aliasToCanonical[key]
    }

    /// Aliases declared for a given canonical foodName, for substring
    /// scanning. Empty array when the entry has no aliases.
    func aliases(forCanonical canonical: String) -> [String] {
        canonicalToAliases[canonical.lowercased()] ?? []
    }

    private struct Entry: Decodable {
        let name: String
        let gi: Int
        let aliases: [String]
    }
}
