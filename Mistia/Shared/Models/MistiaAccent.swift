import SwiftUI

enum MistiaAccent: String, Codable {
    case mint
    case teal
    case cyan
    case indigo
    case amber
    case coral
    case rose
    case slate
    case sky
    case purple

    var color: Color {
        switch self {
        case .mint:
            .mint
        case .teal:
            .teal
        case .cyan:
            .cyan
        case .indigo:
            .indigo
        case .amber:
            Color(red: 0.97, green: 0.66, blue: 0.25)
        case .coral:
            Color(red: 0.98, green: 0.46, blue: 0.41)
        case .rose:
            Color(red: 0.96, green: 0.36, blue: 0.56)
        case .slate:
            Color(red: 0.55, green: 0.58, blue: 0.67)
        case .sky:
            Color(red: 0.39, green: 0.68, blue: 1.0)
        case .purple:
            Color(red: 0.43, green: 0.23, blue: 0.76)
        }
    }
}
