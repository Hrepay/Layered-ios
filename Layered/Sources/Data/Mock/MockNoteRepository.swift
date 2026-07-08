import Foundation

final class MockNoteRepository: NoteRepositoryProtocol {
    func createNote(familyId: String, note: Note) async throws -> Note {
        note
    }

    func getNotes(familyId: String) async throws -> [Note] {
        MockData.notes
    }

    func updateNote(familyId: String, note: Note) async throws {}

    func deleteNote(familyId: String, noteId: String) async throws {}
}
