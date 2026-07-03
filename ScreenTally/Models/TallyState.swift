import SwiftUI

/// Represents the tally state for a monitored source
enum TallyState: String, Codable, Sendable {
    case clear
    case preview
    case program
    case previewProgram

    /// The border color for this tally state
    var color: NSColor {
        switch self {
        case .clear:
            return .clear
        case .preview:
            return NSColor(red: 0, green: 1, blue: 0, alpha: 1) // Bright green
        case .program, .previewProgram:
            return NSColor(red: 1, green: 0, blue: 0, alpha: 1) // Bright red
        }
    }

    /// SwiftUI color for UI elements
    var swiftUIColor: Color {
        switch self {
        case .clear:
            return .gray
        case .preview:
            return .green
        case .program, .previewProgram:
            return .red
        }
    }

    /// Whether the border should be visible
    var showsBorder: Bool {
        self != .clear
    }

    /// Human-readable label
    var label: String {
        switch self {
        case .clear:
            return "Clear"
        case .preview:
            return "Preview"
        case .program:
            return "Program"
        case .previewProgram:
            return "Program"
        }
    }
}

/// Information about a TSL source
struct SourceInfo: Identifiable, Equatable, Sendable {
    let index: Int
    var label: String
    var tally: TallyState

    var id: Int { index }

    /// Display name for the source picker
    var displayName: String {
        if label.isEmpty {
            return "Source \(index)"
        }
        return "\(index): \(label)"
    }
}
