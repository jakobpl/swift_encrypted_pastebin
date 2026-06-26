import CryptoKit
import Foundation

struct VaultService {
    enum VaultServiceError: Error {
        case missingVault
        case invalidVault
        case invalidKeyDerivationMetadata
        case unlockFailed
        case missingDerivedKey
        case archivedVaultNotFound
    }

    struct VaultUnlockResult {
        let key: SymmetricKey
        let payload: VaultPayload
    }

    struct ArchivedVault: Identifiable, Equatable {
        let id: String
        let fileName: String
        let modifiedAt: Date
        let byteCount: Int64
    }

    private let fileManager: FileManager
    private let keyDerivationService: KeyDerivationService
    private let cryptoService: CryptoService
    private static let validationPayloadPlaintext = Data([
        0x57, 0x72, 0x69, 0x74, 0x65, 0x72, 0x20, 0x76,
        0x61, 0x75, 0x6c, 0x74, 0x20, 0x76, 0x31
    ])

    init(
        fileManager: FileManager = .default,
        keyDerivationService: KeyDerivationService = KeyDerivationService(),
        cryptoService: CryptoService = CryptoService()
    ) {
        self.fileManager = fileManager
        self.keyDerivationService = keyDerivationService
        self.cryptoService = cryptoService
    }

    var applicationSupportDirectory: URL {
        get throws {
            try fileManager.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: false
            )
        }
    }

    var vaultDirectoryURL: URL {
        get throws {
            try applicationSupportDirectory
                .appendingPathComponent("Writer", isDirectory: true)
        }
    }

    var vaultFileURL: URL {
        get throws {
            try vaultDirectoryURL
                .appendingPathComponent("vault.writer", isDirectory: false)
        }
    }

    func vaultDirectoryExists() -> Bool {
        guard let url = try? vaultDirectoryURL else {
            return false
        }

        var isDirectory: ObjCBool = false
        let exists = fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory)
        return exists && isDirectory.boolValue
    }

    func vaultFileExists() -> Bool {
        guard let url = try? vaultFileURL else {
            return false
        }

        var isDirectory: ObjCBool = false
        let exists = fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory)
        return exists && !isDirectory.boolValue
    }

    func ensureVaultDirectoryExists() throws {
        let directoryURL = try vaultDirectoryURL

        if !vaultDirectoryExists() {
            try fileManager.createDirectory(
                at: directoryURL,
                withIntermediateDirectories: true
            )
        }
    }

    func createVaultIfNeeded() throws {
        try ensureVaultDirectoryExists()

        let fileURL = try vaultFileURL
        if !vaultFileExists() || isEmptyFile(at: fileURL) {
            try writeVaultFile(makeNewVaultFile(), to: fileURL)
        }
    }

    func loadVaultFile() throws -> VaultFile? {
        guard vaultFileExists() else {
            return nil
        }

        let data = try Data(contentsOf: try vaultFileURL)
        return try Self.decoder.decode(VaultFile.self, from: data)
    }

    func vaultNeedsCreation() -> Bool {
        guard vaultFileExists() else {
            return true
        }

        guard let vaultFile = try? loadVaultFile() else {
            return false
        }

        return vaultFile.encryptedPayload.isEmptyPlaceholder
    }

    func createVault(password: String) throws -> VaultUnlockResult {
        try ensureVaultDirectoryExists()

        let metadata = try keyDerivationService.makeMetadata()
        let key = try keyDerivationService.deriveKey(from: password, metadata: metadata)
        let payload = VaultPayload.singleEditorNote(body: "")
        let payloadData = try encodePayload(payload)
        let encryptedPayload = try cryptoService.encrypt(
            payloadData,
            using: key
        )
        let vaultFile = VaultFile(
            formatVersion: 1,
            createdAt: Date(),
            keyDerivation: VaultKeyDerivationMetadata(metadata: metadata),
            encryption: .aes256GCM,
            encryptedPayload: VaultEncryptedPayload(payload: encryptedPayload)
        )

        try writeVaultFile(vaultFile, to: try vaultFileURL)
        return VaultUnlockResult(key: key, payload: payload)
    }

    func unlockVault(password: String) throws -> VaultUnlockResult {
        let vaultFile: VaultFile?
        do {
            vaultFile = try loadVaultFile()
        } catch {
            throw VaultServiceError.invalidVault
        }

        guard let vaultFile else {
            throw VaultServiceError.missingVault
        }

        guard isSupportedVaultFile(vaultFile) else {
            throw VaultServiceError.invalidVault
        }

        guard let metadata = keyDerivationMetadata(from: vaultFile.keyDerivation) else {
            throw VaultServiceError.invalidKeyDerivationMetadata
        }

        guard let encryptedPayload = vaultFile.encryptedPayload.encryptedPayload(),
              !vaultFile.encryptedPayload.isEmptyPlaceholder
        else {
            throw VaultServiceError.invalidVault
        }

        let key = try keyDerivationService.deriveKey(from: password, metadata: metadata)
        let decrypted = try cryptoService.decrypt(encryptedPayload, using: key)

        if decrypted == Self.validationPayloadPlaintext {
            return VaultUnlockResult(key: key, payload: .singleEditorNote(body: ""))
        }

        if let payload = try? Self.decoder.decode(VaultPayload.self, from: decrypted) {
            return VaultUnlockResult(key: key, payload: payload)
        }

        guard let editorText = String(data: decrypted, encoding: .utf8) else {
            throw VaultServiceError.unlockFailed
        }

        return VaultUnlockResult(key: key, payload: .singleEditorNote(body: editorText))
    }

    func moveCurrentVaultAsideForReplacement() throws -> URL {
        guard vaultFileExists() else {
            throw VaultServiceError.missingVault
        }

        let fileURL = try vaultFileURL
        let archivedURL = try availableArchivedVaultURL(reason: "corrupt")
        try fileManager.moveItem(at: fileURL, to: archivedURL)
        return archivedURL
    }

    func moveCurrentVaultAsideForNewVault() throws -> URL {
        guard vaultFileExists() else {
            throw VaultServiceError.missingVault
        }

        let fileURL = try vaultFileURL
        let archivedURL = try availableArchivedVaultURL(reason: "archived")
        try fileManager.moveItem(at: fileURL, to: archivedURL)
        return archivedURL
    }

    func archivedVaults() throws -> [ArchivedVault] {
        guard vaultDirectoryExists() else {
            return []
        }

        let directoryURL = try vaultDirectoryURL
        let fileURLs = try fileManager.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        )

        return try fileURLs
            .filter { $0.lastPathComponent.hasPrefix("vault.writer.archived.") }
            .map { url in
                let resourceValues = try url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
                return ArchivedVault(
                    id: url.lastPathComponent,
                    fileName: url.lastPathComponent,
                    modifiedAt: resourceValues.contentModificationDate ?? .distantPast,
                    byteCount: Int64(resourceValues.fileSize ?? 0)
                )
            }
            .sorted { $0.modifiedAt > $1.modifiedAt }
    }

    func restoreArchivedVault(id: String) throws {
        let archivedVault = try archivedVaults().first { $0.id == id }
        guard let archivedVault else {
            throw VaultServiceError.archivedVaultNotFound
        }

        let directoryURL = try vaultDirectoryURL
        let archivedURL = directoryURL.appendingPathComponent(archivedVault.fileName)

        if vaultFileExists() {
            _ = try moveCurrentVaultAsideForNewVault()
        }

        try fileManager.moveItem(at: archivedURL, to: try vaultFileURL)
    }

    func deleteArchivedVault(id: String) throws {
        let archivedVault = try archivedVaults().first { $0.id == id }
        guard let archivedVault else {
            throw VaultServiceError.archivedVaultNotFound
        }

        let archivedURL = try vaultDirectoryURL
            .appendingPathComponent(archivedVault.fileName)
        try fileManager.removeItem(at: archivedURL)
    }

    func savePayload(_ payload: VaultPayload, using key: SymmetricKey) throws {
        guard let vaultFile = try loadVaultFile() else {
            throw VaultServiceError.missingVault
        }

        let plaintext = try encodePayload(payload)
        let encryptedPayload = try cryptoService.encrypt(plaintext, using: key)
        let updatedVaultFile = VaultFile(
            formatVersion: vaultFile.formatVersion,
            createdAt: vaultFile.createdAt,
            keyDerivation: vaultFile.keyDerivation,
            encryption: vaultFile.encryption,
            encryptedPayload: VaultEncryptedPayload(payload: encryptedPayload)
        )

        try writeVaultFile(updatedVaultFile, to: try vaultFileURL)
    }

    #if DEBUG
    func validateVaultFileForDebug() throws {
        guard vaultFileExists() else {
            return
        }

        guard let vaultFile = try? loadVaultFile() else {
            return
        }

        guard vaultFile.formatVersion >= 1,
              !vaultFile.keyDerivation.algorithm.isEmpty,
              Data(base64Encoded: vaultFile.keyDerivation.salt) != nil,
              vaultFile.keyDerivation.iterations > 0,
              vaultFile.keyDerivation.keyLength == KeyDerivationService.defaultKeyByteCount,
              !vaultFile.encryption.algorithm.isEmpty
        else {
            assertionFailure("Vault file validation failed")
            return
        }

        let rawVaultData = try Data(contentsOf: try vaultFileURL)
        let forbiddenPlaintextMarkers = ["password", "derivedKey"]
        if let rawVaultString = String(data: rawVaultData, encoding: .utf8) {
            let lowercased = rawVaultString.lowercased()
            for marker in forbiddenPlaintextMarkers {
                precondition(!lowercased.contains(marker.lowercased()), "Vault file contains forbidden plaintext marker")
            }
        }
    }
    #endif

    private func makeNewVaultFile() throws -> VaultFile {
        VaultFile(
            formatVersion: 1,
            createdAt: Date(),
            keyDerivation: VaultKeyDerivationMetadata(
                metadata: try keyDerivationService.makeMetadata()
            ),
            encryption: .aes256GCM,
            encryptedPayload: .emptyPlaceholder
        )
    }

    private func keyDerivationMetadata(from vaultMetadata: VaultKeyDerivationMetadata) -> KeyDerivationMetadata? {
        guard let algorithm = KeyDerivationMetadata.Algorithm(rawValue: vaultMetadata.algorithm),
              let salt = Data(base64Encoded: vaultMetadata.salt),
              vaultMetadata.iterations > 0,
              vaultMetadata.keyLength == KeyDerivationService.defaultKeyByteCount
        else {
            return nil
        }

        return KeyDerivationMetadata(
            algorithm: algorithm,
            salt: salt,
            iterations: vaultMetadata.iterations,
            keyLength: vaultMetadata.keyLength
        )
    }

    private func isSupportedVaultFile(_ vaultFile: VaultFile) -> Bool {
        vaultFile.formatVersion == 1
            && vaultFile.encryption.algorithm == VaultEncryptionMetadata.aes256GCM.algorithm
    }

    private func writeVaultFile(_ vaultFile: VaultFile, to url: URL) throws {
        let data = try Self.encoder.encode(vaultFile)
        try data.write(to: url, options: .atomic)
    }

    private func encodePayload(_ payload: VaultPayload) throws -> Data {
        try Self.encoder.encode(payload)
    }

    private func availableArchivedVaultURL(reason: String) throws -> URL {
        let fileURL = try vaultFileURL
        let timestamp = Int(Date().timeIntervalSince1970)
        let baseName = "\(fileURL.lastPathComponent).\(reason).\(timestamp)"
        var candidate = fileURL.deletingLastPathComponent().appendingPathComponent(baseName)
        var suffix = 1

        while fileManager.fileExists(atPath: candidate.path) {
            candidate = fileURL.deletingLastPathComponent()
                .appendingPathComponent("\(baseName).\(suffix)")
            suffix += 1
        }

        return candidate
    }

    private func isEmptyFile(at url: URL) -> Bool {
        guard let attributes = try? fileManager.attributesOfItem(atPath: url.path),
              let fileSize = attributes[.size] as? NSNumber
        else {
            return false
        }

        return fileSize.intValue == 0
    }
}

private extension VaultService {
    static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()

    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}
