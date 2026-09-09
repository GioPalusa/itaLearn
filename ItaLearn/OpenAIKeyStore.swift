import Foundation
import Observation
import Security

/// A user-owned credential, isolated from preferences, backups and learning data.
actor OpenAIKeyStore {
    static let shared = OpenAIKeyStore()

    private var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: "ItaLearn.OpenAI",
         kSecAttrAccount as String: "user-api-key",
         kSecAttrSynchronizable as String: false,
         kSecUseDataProtectionKeychain as String: true]
    }

    func read() throws -> String? {
        var search = query
        search[kSecReturnData as String] = true
        search[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(search as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data,
              let key = String(data: data, encoding: .utf8) else {
            throw KeyStoreError.operationFailed
        }
        return key
    }

    func save(_ input: String) throws {
        let key = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard key.hasPrefix("sk-"), key.count >= 20,
              !key.contains(where: { $0.isWhitespace || $0 == "\\" }) else {
            throw KeyStoreError.invalidFormat
        }
        let values: [String: Any] = [
            kSecValueData as String: Data(key.utf8),
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]
        var add = query
        add.merge(values) { _, new in new }
        let status = SecItemAdd(add as CFDictionary, nil)
        if status == errSecDuplicateItem {
            guard SecItemUpdate(query as CFDictionary, values as CFDictionary) == errSecSuccess else {
                throw KeyStoreError.operationFailed
            }
        } else if status != errSecSuccess {
            throw KeyStoreError.operationFailed
        }
    }

    func delete() throws {
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeyStoreError.operationFailed
        }
    }
}

nonisolated enum KeyStoreError: LocalizedError {
    case invalidFormat, operationFailed
    var errorDescription: String? {
        switch self {
        case .invalidFormat: "Kontrollera API-nyckeln. Klistra in den utan mellanslag eller extra tecken."
        case .operationFailed: "Nyckelringen kunde inte öppnas. Lås upp enheten och försök igen."
        }
    }
}

@MainActor @Observable
final class OpenAIAccess {
    private(set) var isReady = false
    private(set) var hasKey = false
    private(set) var revision = 0
    var errorMessage: String?

    func load() async {
        do {
            hasKey = try await OpenAIKeyStore.shared.read() != nil
            errorMessage = nil
        } catch { errorMessage = error.localizedDescription }
        isReady = true
    }

    func save(_ key: String) async -> Bool {
        do {
            try await OpenAIKeyStore.shared.save(key)
            hasKey = true
            revision += 1
            errorMessage = nil
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func remove() async {
        do {
            try await OpenAIKeyStore.shared.delete()
            hasKey = false
            revision += 1
            errorMessage = nil
        } catch { errorMessage = error.localizedDescription }
    }
}
