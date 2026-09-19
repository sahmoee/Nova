// QAChecklist+Nova.swift
import Foundation

enum NovaQAChecklist {

    static var sections: [QAChecklistSection] { [
        QAChecklistSection(number: 1, title: "Notes & Editing", items: [
            QACheckItem(ticket: "QA-NV-01-01", text: "Create note saves with correct timestamp", blocker: true),
            QACheckItem(ticket: "QA-NV-01-02", text: "Rich text formatting (bold, italic, headers) renders correctly"),
            QACheckItem(ticket: "QA-NV-01-03", text: "Note edits persist after backgrounding and returning"),
            QACheckItem(ticket: "QA-NV-01-04", text: "Undo/redo works through multiple edit steps"),
            QACheckItem(ticket: "QA-NV-01-05", text: "Delete note moves to trash; restore brings it back"),
        ]),

        QAChecklistSection(number: 2, title: "Organisation & Search", items: [
            QACheckItem(ticket: "QA-NV-02-01", text: "Folders create and nest correctly"),
            QACheckItem(ticket: "QA-NV-02-02", text: "Move note to folder updates list immediately"),
            QACheckItem(ticket: "QA-NV-02-03", text: "Tags apply and filter notes correctly"),
            QACheckItem(ticket: "QA-NV-02-04", text: "Search finds notes by title and body within 500 ms"),
            QACheckItem(ticket: "QA-NV-02-05", text: "Pinned notes appear at top of list"),
        ]),

        QAChecklistSection(number: 3, title: "Attachments & Media", items: [
            QACheckItem(ticket: "QA-NV-03-01", text: "Image attachment inserts and renders inline"),
            QACheckItem(ticket: "QA-NV-03-02", text: "PDF attachment opens in preview"),
            QACheckItem(ticket: "QA-NV-03-03", text: "Audio recording attaches and plays back correctly"),
        ]),

        QAChecklistSection(number: 4, title: "Sync & iCloud", items: [
            QACheckItem(ticket: "QA-NV-04-01", text: "Note created on iPhone appears on iPad within 30 s", blocker: true),
            QACheckItem(ticket: "QA-NV-04-02", text: "Conflict resolution keeps newest version; flags older"),
            QACheckItem(ticket: "QA-NV-04-03", text: "Offline edits queue and sync on reconnect", blocker: true),
        ]),

        QAChecklistSection(number: 5, title: "Performance", items: [
            QACheckItem(ticket: "QA-NV-05-01", text: "Note list loads instantly with 500+ notes"),
            QACheckItem(ticket: "QA-NV-05-02", text: "Large note (10 000 words) opens in < 1 s"),
            QACheckItem(ticket: "QA-NV-05-03", text: "Search index rebuilds without UI freeze after bulk import"),
        ]),
    ]}

    static var titleMap: [String: String] {
        Dictionary(uniqueKeysWithValues:
            sections.flatMap(\.items).map { ($0.ticket, $0.text) })
    }
}
