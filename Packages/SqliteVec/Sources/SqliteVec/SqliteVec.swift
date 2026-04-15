import CSqliteVec

/// Registers the sqlite-vec extension on a raw SQLite database handle.
///
/// Call this from GRDB's `Configuration.prepareDatabase` closure to enable
/// vec0 virtual tables for vector similarity search.
///
/// - Parameter db: The raw `OpaquePointer` (`sqlite3*`) from GRDB's `Database.sqliteConnection`.
/// - Returns: `true` if registration succeeded.
@discardableResult
public func registerSqliteVec(_ db: OpaquePointer) -> Bool {
    sqlite_vec_register(db) == 0 // SQLITE_OK
}
