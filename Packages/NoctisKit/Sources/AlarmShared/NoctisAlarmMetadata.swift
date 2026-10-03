import AlarmKit

/// The extra data NOCTIS attaches to its alarm. There isn't any: AlarmKit asks for a
/// metadata type, and the app and the alarm widget extension must agree on it, so it
/// lives here, in a module with nothing else in it.
public struct NoctisAlarmMetadata: AlarmMetadata {
    public init() {}
}
