import Foundation

/// 街坊电话号码（residentID → 号码）。示範街坊全空。
/// 以后 Resident 加电话字段时并入模型，删掉这个表。
enum PhoneBook {
    static let numbers: [String: String] = [:]

    /// 只留数字和 +，空的当没有。
    static func number(for id: String) -> String? {
        guard let raw = numbers[id] else { return nil }
        let n = raw.filter { $0.isNumber || $0 == "+" }
        return n.isEmpty ? nil : n
    }
}
