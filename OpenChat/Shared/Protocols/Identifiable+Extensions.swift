import Foundation

extension Identifiable where ID == String {
    var stableID: String { id }
}
