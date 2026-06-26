import Foundation

struct VaultFile: Codable, Equatable {
    let formatVersion: Int
    let createdAt: Date
    let keyDerivation: VaultKeyDerivationMetadata
    let encryption: VaultEncryptionMetadata
    let encryptedPayload: VaultEncryptedPayload
}

struct VaultKeyDerivationMetadata: Codable, Equatable {
    let algorithm: String
    let salt: String
    let iterations: UInt32
    let keyLength: Int

    init(metadata: KeyDerivationMetadata) {
        algorithm = metadata.algorithm.rawValue
        salt = metadata.salt.base64EncodedString()
        iterations = metadata.iterations
        keyLength = metadata.keyLength
    }
}

struct VaultEncryptionMetadata: Codable, Equatable {
    let algorithm: String

    static let aes256GCM = VaultEncryptionMetadata(algorithm: "AES-256-GCM")
}

struct VaultEncryptedPayload: Codable, Equatable {
    let nonce: String
    let ciphertext: String
    let authenticationTag: String

    static let emptyPlaceholder = VaultEncryptedPayload(
        nonce: "",
        ciphertext: "",
        authenticationTag: ""
    )

    init(payload: EncryptedPayload) {
        nonce = payload.nonce.base64EncodedString()
        ciphertext = payload.ciphertext.base64EncodedString()
        authenticationTag = payload.authenticationTag.base64EncodedString()
    }

    private init(nonce: String, ciphertext: String, authenticationTag: String) {
        self.nonce = nonce
        self.ciphertext = ciphertext
        self.authenticationTag = authenticationTag
    }

    var isEmptyPlaceholder: Bool {
        nonce.isEmpty && ciphertext.isEmpty && authenticationTag.isEmpty
    }

    func encryptedPayload() -> EncryptedPayload? {
        guard let nonceData = Data(base64Encoded: nonce),
              let ciphertextData = Data(base64Encoded: ciphertext),
              let authenticationTagData = Data(base64Encoded: authenticationTag)
        else {
            return nil
        }

        return EncryptedPayload(
            nonce: nonceData,
            ciphertext: ciphertextData,
            authenticationTag: authenticationTagData
        )
    }
}
