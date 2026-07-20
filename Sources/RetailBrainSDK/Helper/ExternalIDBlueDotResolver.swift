import Foundation
import Mappedin

enum ExternalIDBlueDotResolver {
    // External ID format required by host integration: aisle + module, no separators.
    static func buildExternalID(aisle: String, module: String) -> String {
        normalizeExternalIDComponent(aisle) + normalizeExternalIDComponent(module)
    }

    static func resolveSpace(by externalID: String, in spaces: [Space]) -> Space? {
        let normalizedExternalID = normalizeLookup(externalID)
        guard !normalizedExternalID.isEmpty else { return nil }

        return spaces.first { space in
            let candidates = externalIDCandiates(for: space)
            return candidates.contains(normalizedExternalID)
        }
    }

    private static func externalIDCandiates(for space: Space) -> Set<String> {
        var values = Set<String>()

        let mirroredValues = collectStringValues(
            in: space,
            preferredLabels: ["externalId", "externalID", "externalIdentifier", "external_id"],
            maxDepth: 5
        )

        for value in mirroredValues {
            let normalized = normalizeLookup(value)
            if !normalized.isEmpty {
                values.insert(normalized)
            }
        }

        return values
    }

    private static func normalizeExternalIDComponent(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "-", with: "")
            .lowercased()
    }

    private static func normalizeLookup(_ value: String) -> String {
        normalizeExternalIDComponent(value)
    }

    private static func collectStringValues(
        in value: Any,
        preferredLabels: [String],
        maxDepth: Int
    ) -> [String] {
        guard maxDepth >= 0 else { return [] }

        if let stringValue = value as? String {
            return [stringValue]
        }

        let mirror = Mirror(reflecting: value)
        guard !mirror.children.isEmpty else { return [] }

        let orderedChildren = mirror.children.sorted { lhs, rhs in
            labelPriority(lhs.label, preferredLabels: preferredLabels) <
            labelPriority(rhs.label, preferredLabels: preferredLabels)
        }

        var values: [String] = []
        for child in orderedChildren {
            values.append(contentsOf: collectStringValues(
                in: child.value,
                preferredLabels: preferredLabels,
                maxDepth: maxDepth - 1
            ))
        }

        return values
    }

    private static func labelPriority(_ label: String?, preferredLabels: [String]) -> Int {
        guard let label else { return Int.max }
        if let index = preferredLabels.firstIndex(where: { $0.caseInsensitiveCompare(label) == .orderedSame }) {
            return index
        }
        return Int.max - 1
    }
}
