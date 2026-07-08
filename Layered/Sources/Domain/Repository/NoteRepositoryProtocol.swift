import Foundation

protocol NoteRepositoryProtocol {
    func createNote(familyId: String, note: Note) async throws -> Note
    func getNotes(familyId: String) async throws -> [Note]
    func updateNote(familyId: String, note: Note) async throws
    func deleteNote(familyId: String, noteId: String) async throws
}
