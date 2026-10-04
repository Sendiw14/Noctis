import DesignSystem
import SwiftUI

/// What the controls take from the app's palette (APP_RULES.md R48). A control is drawn by the system, in flat template shapes; the one thing
/// NOCTIS chooses is its tint, and it is the app's own lavender (light and dark), never a color of its own.
public enum ControlStyle {
    public static var tint: Color { NoctisAppColor.lavender }
}
