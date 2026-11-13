import Foundation

/// Translate presentation values without changing persisted identifiers or classifier keys.
enum L10n {
    static func layout(_ value: String) -> String {
        switch value {
        case "Full grid": String(localized: "Full grid")
        case "Columns": String(localized: "Columns")
        case "Left / right": String(localized: "Left / right")
        case "Rows": String(localized: "Rows")
        case "Top / bottom": String(localized: "Top / bottom")
        case "Corners": String(localized: "Corners")
        default: value
        }
    }
    static func gate(_ value: String) -> String {
        switch value {
        case "too soft": String(localized: "Too soft")
        case "still moving": String(localized: "Still moving")
        case "lid moved": String(localized: "Lid moved")
        case "click": String(localized: "Click detected")
        case "pointer moving": String(localized: "Pointer moving")
        case "typing": String(localized: "Typing")
        case "scroll": String(localized: "Scrolling")
        default: value
        }
    }
    static func icon(_ value: String) -> String {
        switch value {
        case "laptopcomputer": String(localized: "Laptop")
        case "table.furniture": String(localized: "Table")
        case "lamp.desk": String(localized: "Desk lamp")
        case "studentdesk": String(localized: "Desk")
        case "figure.seated.side": String(localized: "Seated")
        case "sofa": String(localized: "Sofa")
        case "chair.lounge": String(localized: "Lounge chair")
        case "bed.double": String(localized: "Bed")
        case "house": String(localized: "Home")
        case "building.2": String(localized: "Building")
        case "briefcase": String(localized: "Briefcase")
        case "books.vertical": String(localized: "Books")
        case "cup.and.saucer": String(localized: "Coffee")
        case "fork.knife": String(localized: "Dining")
        case "airplane": String(localized: "Airplane")
        case "tram": String(localized: "Tram")
        case "car": String(localized: "Car")
        case "tree": String(localized: "Tree")
        case "beach.umbrella": String(localized: "Beach umbrella")
        case "moon": String(localized: "Moon")
        default: value
        }
    }
}
