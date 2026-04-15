#ifndef CSQLITEVEC_H
#define CSQLITEVEC_H

#include <sqlite3.h>

/// Register sqlite-vec extension with a database connection.
/// Call this in GRDB's Configuration.prepareDatabase closure.
int sqlite_vec_register(sqlite3 *db);

#endif
