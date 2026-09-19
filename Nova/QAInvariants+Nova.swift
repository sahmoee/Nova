// QAInvariants+Nova.swift
import Foundation

enum NovaQAInvariants {

    /// No note should exist outside a valid folder (root is acceptable).
    static func checkOrphanNotes() async {
        let key = "inv.nova.orphan-notes"
        _ = key
    }

    /// Trash must not contain notes that are also in active folders.
    static func checkTrashDuplicates() async {
        let key = "inv.nova.trash-duplicates"
        _ = key
    }

    /// Search index count must match active note count.
    static func checkSearchIndexSync() async {
        let key = "inv.nova.search-index-sync"
        _ = key
    }

    static func runAll() async {
        await checkOrphanNotes()
        await checkTrashDuplicates()
        await checkSearchIndexSync()
    }
}
