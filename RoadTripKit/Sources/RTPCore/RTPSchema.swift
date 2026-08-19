import Foundation
import SwiftData

/// Central place listing every persisted model, so the app target and tests
/// build their `ModelContainer` from a single source of truth.
public enum RTPSchema {
    public static let models: [any PersistentModel.Type] = [
        Trip.self,
        Anchor.self,
        RouteLeg.self,
        TripDay.self,
        TripPhoto.self
    ]

    /// Builds a `ModelContainer` for the given configurations. Local storage
    /// only in v1 (`cloudKitDatabase: .none`); flipping this on later is a
    /// configuration change, not a migration, because the schema above is
    /// already CloudKit-compatible (optional relationships with inverses,
    /// no unique constraints, defaults on every attribute).
    public static func makeContainer(inMemory: Bool = false) throws -> ModelContainer {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: inMemory, cloudKitDatabase: .none)
        return try ModelContainer(for: Schema(models), configurations: [configuration])
    }
}
