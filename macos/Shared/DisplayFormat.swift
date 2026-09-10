import Foundation

enum Display {
    static func money(_ value: Double) -> String {
        guard value.isFinite, value >= 0 else { return "—" }
        return value.formatted(.currency(code: "USD").locale(Locale(identifier: "en_US")))
    }
    static func tokens(_ value: Double) -> String {
        guard value.isFinite, value >= 0 else { return "—" }
        for (scale, suffix) in [(1e9, "B"), (1e6, "M"), (1e3, "K")] {
            if value >= scale {
                return (value / scale).formatted(.number.precision(.fractionLength(0...1))) + suffix
            }
        }
        return value.formatted(.number.precision(.fractionLength(0)))
    }
    static func runtime(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "—" }
        if seconds < 60 { return "<1m" }
        if seconds < 3600 { return "\(Int(seconds / 60))m" }
        return
            "\(Int(min(seconds / 3600, 99999)))h \(Int(seconds.truncatingRemainder(dividingBy: 3600) / 60))m"
    }
}
