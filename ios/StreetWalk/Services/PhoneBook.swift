import Foundation

/// Neighbor phone numbers keyed by residentID; demo residents have none.
/// Merge into Resident and remove this lookup table if phone numbers become a model field.
enum PhoneBook {
    static let numbers: [String: String] = [:]

    /// Keep only digits and +; empty means absent.
    static func number(for id: String) -> String? {
        guard let raw = numbers[id] else { return nil }
        let n = raw.filter { $0.isNumber || $0 == "+" }
        return n.isEmpty ? nil : n
    }
}
