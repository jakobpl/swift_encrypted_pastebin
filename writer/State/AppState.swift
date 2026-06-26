import Combine
import CryptoKit
import Foundation

enum LockState {
    case locked
    case unlocked
}

@MainActor
final class AppState: ObservableObject {
    @Published private(set) var lockState: LockState = .locked
    @Published private(set) var vaultDirectoryExists = false
    @Published private(set) var vaultFileExists = false
    @Published private(set) var vaultNeedsCreation = true
    @Published private(set) var canReplaceCorruptedVault = false
    @Published private(set) var archivedVaults: [VaultService.ArchivedVault] = []
    @Published private(set) var notes: [VaultNote] = []
    @Published private(set) var selectedNoteID: String?
    @Published private(set) var isAutoSaveEnabled = false
    @Published var authenticationErrorMessage: String?
    @Published var editorStatusMessage: String?

    private let vaultService: VaultService
    private var derivedKey: SymmetricKey?
    private var autoSaveTask: Task<Void, Never>?
    private let autoSaveDelayNanoseconds: UInt64 = 900_000_000

    init(vaultService: VaultService? = nil) {
        self.vaultService = vaultService ?? VaultService()
        runDebugSelfChecks()
        prepareVaultFile()
    }

    var isLocked: Bool {
        lockState == .locked
    }

    func unlockPlaceholder() {
        lockState = .unlocked
    }

    func lock() {
        autoSaveTask?.cancel()
        autoSaveTask = nil
        derivedKey = nil
        notes = []
        selectedNoteID = nil
        editorStatusMessage = nil
        lockState = .locked
    }

    func createOrUnlockVault(password: String) {
        authenticationErrorMessage = nil
        canReplaceCorruptedVault = false

        do {
            let unlockResult: VaultService.VaultUnlockResult
            if vaultNeedsCreation {
                unlockResult = try vaultService.createVault(password: password)
            } else {
                unlockResult = try vaultService.unlockVault(password: password)
            }

            derivedKey = unlockResult.key
            loadPayloadIntoMemory(unlockResult.payload)
            editorStatusMessage = nil
            lockState = .unlocked
            refreshVaultStatus()
        } catch {
            derivedKey = nil
            notes = []
            selectedNoteID = nil
            editorStatusMessage = nil
            lockState = .locked
            authenticationErrorMessage = authenticationErrorMessage(for: error)
            canReplaceCorruptedVault = isRecoverableCorruptedVaultError(error)
        }
    }

    func replaceCorruptedVaultAfterConfirmation() {
        derivedKey = nil
        notes = []
        selectedNoteID = nil
        editorStatusMessage = nil
        lockState = .locked

        do {
            _ = try vaultService.moveCurrentVaultAsideForReplacement()
            refreshVaultStatus()
            canReplaceCorruptedVault = false
            authenticationErrorMessage = "Corrupted vault moved aside. Create a new vault."
        } catch {
            refreshVaultStatus()
            canReplaceCorruptedVault = isRecoverableCorruptedVaultError(error)
            authenticationErrorMessage = "Could not replace corrupted vault."
        }
    }

    func startNewVaultAfterForgettingPassword() {
        derivedKey = nil
        notes = []
        selectedNoteID = nil
        editorStatusMessage = nil
        lockState = .locked

        do {
            _ = try vaultService.moveCurrentVaultAsideForNewVault()
            refreshVaultStatus()
            canReplaceCorruptedVault = false
            authenticationErrorMessage = "Previous vault moved aside. Create a new vault."
        } catch {
            refreshVaultStatus()
            canReplaceCorruptedVault = false
            authenticationErrorMessage = "Could not start a new vault."
        }
    }

    func restoreArchivedVault(id: String) {
        derivedKey = nil
        notes = []
        selectedNoteID = nil
        editorStatusMessage = nil
        lockState = .locked

        do {
            try vaultService.restoreArchivedVault(id: id)
            refreshVaultStatus()
            canReplaceCorruptedVault = false
            authenticationErrorMessage = "Archived vault restored. Unlock with that vault password."
        } catch {
            refreshVaultStatus()
            canReplaceCorruptedVault = false
            authenticationErrorMessage = "Could not restore archived vault."
        }
    }

    func deleteArchivedVault(id: String) {
        derivedKey = nil
        notes = []
        selectedNoteID = nil
        editorStatusMessage = nil
        lockState = .locked

        do {
            try vaultService.deleteArchivedVault(id: id)
            refreshVaultStatus()
            canReplaceCorruptedVault = false
            authenticationErrorMessage = "Archived vault deleted."
        } catch {
            refreshVaultStatus()
            canReplaceCorruptedVault = false
            authenticationErrorMessage = "Could not delete archived vault."
        }
    }

    func saveEditorText() {
        autoSaveTask?.cancel()
        autoSaveTask = nil
        saveCurrentPayload()
    }

    func setAutoSaveEnabled(_ isEnabled: Bool) {
        isAutoSaveEnabled = isEnabled

        if isEnabled {
            scheduleAutoSave()
        } else {
            autoSaveTask?.cancel()
            autoSaveTask = nil
        }
    }

    private func saveCurrentPayload() {
        guard let derivedKey else {
            editorStatusMessage = "Save failed."
            return
        }

        editorStatusMessage = "Saving..."

        do {
            try vaultService.savePayload(currentPayload(), using: derivedKey)
            editorStatusMessage = "Saved."
        } catch {
            editorStatusMessage = "Save failed."
        }
    }

    var selectedNoteBody: String {
        guard let selectedNoteIndex else {
            return ""
        }

        return notes[selectedNoteIndex].body
    }

    func updateSelectedNoteBody(_ body: String) {
        guard let selectedNoteIndex else {
            return
        }

        notes[selectedNoteIndex].body = body
        notes[selectedNoteIndex].title = noteTitle(for: body)
        notes[selectedNoteIndex].updatedAt = Date()
        editorStatusMessage = nil
        scheduleAutoSave()
    }

    func selectNote(id: String) {
        guard notes.contains(where: { $0.id == id }) else {
            return
        }

        selectedNoteID = id
        editorStatusMessage = nil
    }

    func selectPreviousNote() {
        guard let selectedNoteIndex,
              !notes.isEmpty
        else {
            return
        }

        let previousIndex = max(selectedNoteIndex - 1, 0)
        selectedNoteID = notes[previousIndex].id
        editorStatusMessage = nil
    }

    func selectNextNote() {
        guard let selectedNoteIndex,
              !notes.isEmpty
        else {
            return
        }

        let nextIndex = min(selectedNoteIndex + 1, notes.count - 1)
        selectedNoteID = notes[nextIndex].id
        editorStatusMessage = nil
    }

    func createNote() {
        let now = Date()
        let note = VaultNote(
            id: UUID().uuidString,
            title: "Untitled",
            body: "",
            createdAt: now,
            updatedAt: now
        )

        notes.append(note)
        selectedNoteID = note.id
        editorStatusMessage = nil
    }

    func renameNote(id: String, title: String) {
        guard let noteIndex = notes.firstIndex(where: { $0.id == id }) else {
            return
        }

        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        notes[noteIndex].title = trimmedTitle.isEmpty ? "Untitled" : String(trimmedTitle.prefix(40))
        notes[noteIndex].updatedAt = Date()
        saveCurrentPayload()
    }

    func deleteNote(id: String) {
        guard let noteIndex = notes.firstIndex(where: { $0.id == id }) else {
            return
        }

        notes.remove(at: noteIndex)

        if notes.isEmpty {
            createNote()
        } else if selectedNoteID == id {
            let nextIndex = min(noteIndex, notes.count - 1)
            selectedNoteID = notes[nextIndex].id
        }

        saveCurrentPayload()
    }

    private func scheduleAutoSave() {
        guard isAutoSaveEnabled else {
            return
        }

        autoSaveTask?.cancel()
        editorStatusMessage = "Unsaved"

        let delay = autoSaveDelayNanoseconds
        autoSaveTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: delay)
            guard !Task.isCancelled else {
                return
            }

            self?.saveCurrentPayload()
        }
    }

    private func prepareVaultFile() {
        do {
            try vaultService.ensureVaultDirectoryExists()
            _ = try vaultService.loadVaultFile()
        } catch {
            // Keep the app runnable. Future phases can surface safe vault errors.
        }

        refreshVaultStatus()
    }

    private func refreshVaultStatus() {
        vaultDirectoryExists = vaultService.vaultDirectoryExists()
        vaultFileExists = vaultService.vaultFileExists()
        vaultNeedsCreation = vaultService.vaultNeedsCreation()
        archivedVaults = (try? vaultService.archivedVaults()) ?? []
    }

    private var selectedNoteIndex: Int? {
        guard let selectedNoteID else {
            return nil
        }

        return notes.firstIndex(where: { $0.id == selectedNoteID })
    }

    private func loadPayloadIntoMemory(_ payload: VaultPayload) {
        let loadedNotes = payload.notes.isEmpty
            ? VaultPayload.singleEditorNote(body: "").notes
            : payload.notes

        notes = loadedNotes

        if let selectedNoteID = payload.selectedNoteID,
           loadedNotes.contains(where: { $0.id == selectedNoteID }) {
            self.selectedNoteID = selectedNoteID
        } else {
            selectedNoteID = loadedNotes.first?.id
        }
    }

    private func currentPayload() -> VaultPayload {
        VaultPayload(
            formatVersion: 1,
            notes: notes,
            selectedNoteID: selectedNoteID
        )
    }

    private func noteTitle(for body: String) -> String {
        let trimmedTitle = body
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty } ?? ""

        if trimmedTitle.isEmpty {
            return "Untitled"
        }

        return String(trimmedTitle.prefix(40))
    }

    private func authenticationErrorMessage(for error: Error) -> String {
        if vaultNeedsCreation {
            return "Could not create vault."
        }

        guard let vaultError = error as? VaultService.VaultServiceError else {
            return "Could not unlock vault. Check the password or vault file integrity."
        }

        switch vaultError {
        case .missingVault:
            return "Vault file is missing."
        case .invalidVault:
            return "Vault file is corrupted or unsupported."
        case .unlockFailed:
            return "Could not unlock vault. Check the password or vault file integrity."
        case .invalidKeyDerivationMetadata:
            return "Vault key metadata is corrupted or unsupported."
        case .missingDerivedKey:
            return "Could not unlock vault."
        case .archivedVaultNotFound:
            return "Archived vault is missing."
        }
    }

    private func isRecoverableCorruptedVaultError(_ error: Error) -> Bool {
        guard let vaultError = error as? VaultService.VaultServiceError else {
            return false
        }

        switch vaultError {
        case .invalidVault, .invalidKeyDerivationMetadata:
            return true
        case .missingVault, .unlockFailed, .missingDerivedKey, .archivedVaultNotFound:
            return false
        }
    }

    private func runDebugSelfChecks() {
        #if DEBUG
        do {
            try CryptoService.runSelfCheck()
            try KeyDerivationService.runSelfCheck()
            try vaultService.validateVaultFileForDebug()
        } catch {
            assertionFailure("Security self-check failed")
        }
        #endif
    }
}
