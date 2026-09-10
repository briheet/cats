import Foundation

enum Display {
    static func activityAge(_ timestamp: Double?, now: Double = Date().timeIntervalSince1970)
        -> String
    {
        guard let timestamp, timestamp.isFinite, timestamp > 0, now.isFinite, timestamp <= now
        else {
            return "—"
        }
        let age = now - timestamp
        if age < 60 { return "now" }
        if age < 3600 { return "\(Int(age / 60))m ago" }
        if age < 86400 { return "\(Int(age / 3600))h ago" }
        return "\(Int(min(age / 86400, 99999)))d ago"
    }
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
}
