import AppIntents

/// Tells the system the intents in this target are the app's and the widget extension's (they are compiled into both, so a control in the
/// extension can name them and the app can run them).
public struct NoctisIntentKitPackage: AppIntentsPackage {}
