import Foundation

struct SideEffectPolicy: Sendable, Codable, Equatable {
    let allowDatabaseRead: Bool
    let allowDatabaseWrite: Bool
    let requiresUserConfirmationForWrite: Bool

    static let readOnly = SideEffectPolicy(
        allowDatabaseRead: false,
        allowDatabaseWrite: false,
        requiresUserConfirmationForWrite: true
    )
}
