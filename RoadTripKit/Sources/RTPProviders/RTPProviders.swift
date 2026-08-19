import Foundation

/// Marker type for the provider abstraction module. The `MapProvider` protocol
/// and `AppleMapsProvider`/`StubProvider` conformances land in the
/// `provider-layer` work item.
public enum RTPProviders {
    public static let moduleName = "RTPProviders"
}
