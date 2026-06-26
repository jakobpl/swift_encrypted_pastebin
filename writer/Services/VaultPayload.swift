import Foundation

struct VaultPayload: Codable, Equatable {
    let formatVersion: Int
    let notes: [VaultNote]
    let selectedNoteID: String?

    static func singleEditorNote(body: String, now: Date = Date()) -> VaultPayload {
        let note = VaultNote(
            id: "primary",
            title: "Untitled",
            body: body,
            createdAt: now,
            updatedAt: now
        )

        return VaultPayload(
            formatVersion: 1,
            notes: [note],
            selectedNoteID: note.id
        )
    }

    var selectedEditorText: String {
        if let selectedNoteID,
           let selectedNote = notes.first(where: { $0.id == selectedNoteID }) {
            return selectedNote.body
        }

        return notes.first?.body ?? ""
    }
}

struct VaultNote: Codable, Equatable, Identifiable {
    let id: String
    var title: String
    var body: String
    let createdAt: Date
    var updatedAt: Date
}
