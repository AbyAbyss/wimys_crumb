// ScanDatabase.swift
// GRDB stack, schema, migrations. One database file per scan (the file is the
// scope — no `scan_id` on `dirs`).
//
// Phase 1 wires the schema, migrations, and a clean open/close path. Reads and
// writes used by the engine and queries (sections 10–11 of the plan) are added
// in later phases.

import Foundation
import GRDB

final class ScanDatabase {

    /// Pool: many short-lived read connections + one writer. WAL allows reads
    /// during a scan write.
    let pool: DatabasePool
    let url: URL

    init(url: URL) throws {
        self.url = url

        var config = Configuration()
        // Pragmas from plan §11.1
        config.prepareDatabase { db in
            try db.execute(sql: "PRAGMA journal_mode = WAL;")
            try db.execute(sql: "PRAGMA synchronous  = NORMAL;")
            try db.execute(sql: "PRAGMA temp_store   = MEMORY;")
            try db.execute(sql: "PRAGMA mmap_size    = 268435456;")  // 256MB mmap window
            try db.execute(sql: "PRAGMA cache_size   = -50000;")     // 50MB page cache
            // FK enforcement off: the engine inserts dirs in children-first
            // order (rows pop the stack from leaves up), which would otherwise
            // trip the parent_id REFERENCES dirs(id) constraint. The constraint
            // remains in the schema as documentation; cascade behavior for
            // deletes is done explicitly by DeleteService (plan §12.2).
            try db.execute(sql: "PRAGMA foreign_keys = OFF;")
        }

        let parentDir = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: parentDir,
                                                withIntermediateDirectories: true)

        self.pool = try DatabasePool(path: url.path, configuration: config)
        try Self.migrator.migrate(pool)
    }

    deinit {
        // DatabasePool closes on dealloc.
    }

    // MARK: - Migrations

    static var migrator: DatabaseMigrator {
        var m = DatabaseMigrator()

        m.registerMigration("v1_schema") { db in
            // dirs ------------------------------------------------------
            try db.execute(sql: """
            CREATE TABLE dirs (
              id INTEGER PRIMARY KEY,
              parent_id INTEGER REFERENCES dirs(id),
              name TEXT NOT NULL,
              depth INTEGER NOT NULL,
              is_hidden INTEGER NOT NULL DEFAULT 0,
              is_package INTEGER NOT NULL DEFAULT 0,
              mtime INTEGER,
              own_size INTEGER NOT NULL DEFAULT 0,
              file_count INTEGER NOT NULL DEFAULT 0,
              child_dir_count INTEGER NOT NULL DEFAULT 0,
              total_size INTEGER NOT NULL DEFAULT 0,
              descendant_file_count INTEGER NOT NULL DEFAULT 0
            );
            """)
            try db.execute(sql: "CREATE INDEX idx_dirs_parent ON dirs(parent_id);")
            try db.execute(sql: "CREATE INDEX idx_dirs_name   ON dirs(name);")
            try db.execute(sql: "CREATE INDEX idx_dirs_total  ON dirs(total_size DESC);")
            try db.execute(sql: "CREATE INDEX idx_dirs_depth  ON dirs(depth);")

            // large_files -----------------------------------------------
            try db.execute(sql: """
            CREATE TABLE large_files (
              id INTEGER PRIMARY KEY,
              dir_id INTEGER NOT NULL REFERENCES dirs(id),
              name TEXT NOT NULL,
              size INTEGER NOT NULL,
              mtime INTEGER,
              ext TEXT,
              file_type INTEGER NOT NULL
            );
            """)
            try db.execute(sql: "CREATE INDEX idx_large_files_size ON large_files(size DESC);")
            try db.execute(sql: "CREATE INDEX idx_large_files_type ON large_files(file_type, size DESC);")
            try db.execute(sql: "CREATE INDEX idx_large_files_dir  ON large_files(dir_id);")

            // file_type_totals ------------------------------------------
            try db.execute(sql: """
            CREATE TABLE file_type_totals (
              file_type INTEGER PRIMARY KEY,
              total_size INTEGER NOT NULL,
              file_count INTEGER NOT NULL
            );
            """)

            // scans -----------------------------------------------------
            try db.execute(sql: """
            CREATE TABLE scans (
              id INTEGER PRIMARY KEY,
              volume_uuid TEXT NOT NULL,
              volume_name TEXT NOT NULL,
              started_at INTEGER NOT NULL,
              completed_at INTEGER,
              total_used INTEGER,
              total_free INTEGER,
              dir_count INTEGER,
              file_count INTEGER,
              skipped_count INTEGER
            );
            """)

            // snapshot_top_folders --------------------------------------
            try db.execute(sql: """
            CREATE TABLE snapshot_top_folders (
              scan_id INTEGER NOT NULL REFERENCES scans(id),
              path TEXT NOT NULL,
              total_size INTEGER NOT NULL
            );
            """)
            try db.execute(sql: "CREATE INDEX idx_snap_top ON snapshot_top_folders(scan_id);")
        }

        return m
    }
}
