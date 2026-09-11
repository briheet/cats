import Foundation

struct ThemeState: Codable, Equatable {
    var appearance: String
    var colors: [String: String]
}
