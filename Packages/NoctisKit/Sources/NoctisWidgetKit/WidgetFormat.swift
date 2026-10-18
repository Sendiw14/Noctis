import DesignSystem

/// The widgets use the one formatter (`NoctisFormat`, DesignSystem) that Home, the Watch, Siri and Coach use: a duration, a clock time or a window reads the same
/// on every surface because it is made by the same function. This alias is not a copy.
public typealias WidgetFormat = NoctisFormat
