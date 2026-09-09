import Foundation

/// One-line summary of a filter dimension's current selection, shown as
/// secondary text on a collapsed filter row. Names are expected pre-sorted so
/// the "+N" overflow is stable.
enum FilterSummary {
    static func summarize(_ names: [String]) -> String {
        switch names.count {
        case 0: return ""
        case 1: return names[0]
        case 2: return "\(names[0]), \(names[1])"
        default: return "\(names[0]), \(names[1]) +\(names.count - 2)"
        }
    }
}
