import Foundation
import Security

/// Pluggable Keychain accessor — `SystemKeychain` for real use,
/// `InMemoryKeychain` for tests (and the unit test for cascade-delete on
/// camera removal, per ADR-0005).
public protocol KeychainAccessing: Sendable {
    func read(account: String, service: String) throws -> String?
    func write(account: String, service: String, value: String) throws
    func delete(account: String, service: String) throws
    func deleteAll(service: String) throws
}

public enum KeychainError: Error, Sendable, Equatable {
    case osStatus(OSStatus)
    case encoding
}

/// Stores camera passwords (and other app secrets) in macOS Keychain.
///
/// Per ADR-0005 the layout is:
///   - service: `dev.open-reolink`
///   - account: `<cameraId>.admin` — password for CGI access (admin user)
///   - account: `<cameraId>.events` — password for ONVIF events (non-admin user)
public final class CredentialStore: Sendable {
    public enum Role: String, Sendable, CaseIterable {
        case admin
        case events
    }

    public static let defaultService = "dev.open-reolink"

    private let keychain: KeychainAccessing
    private let service: String

    public init(keychain: KeychainAccessing = SystemKeychain(), service: String = CredentialStore.defaultService) {
        self.keychain = keychain
        self.service = service
    }

    public func password(for cameraId: UUID, role: Role) throws -> String? {
        try keychain.read(account: account(cameraId, role), service: service)
    }

    public func setPassword(_ value: String, for cameraId: UUID, role: Role) throws {
        try keychain.write(account: account(cameraId, role), service: service, value: value)
    }

    public func deleteAllPasswords(for cameraId: UUID) throws {
        for role in Role.allCases {
            try keychain.delete(account: account(cameraId, role), service: service)
        }
    }

    private func account(_ cameraId: UUID, _ role: Role) -> String {
        "\(cameraId.uuidString).\(role.rawValue)"
    }
}

// MARK: - System Keychain

public final class SystemKeychain: KeychainAccessing {
    public init() {}

    public func read(account: String, service: String) throws -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw KeychainError.osStatus(status) }
        guard let data = result as? Data, let value = String(data: data, encoding: .utf8) else {
            throw KeychainError.encoding
        }
        return value
    }

    public func write(account: String, service: String, value: String) throws {
        guard let data = value.data(using: .utf8) else { throw KeychainError.encoding }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let attributes: [String: Any] = [
            kSecValueData as String: data,
        ]
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecSuccess { return }
        if status != errSecItemNotFound { throw KeychainError.osStatus(status) }
        var addQuery = query
        addQuery[kSecValueData as String] = data
        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
        guard addStatus == errSecSuccess else { throw KeychainError.osStatus(addStatus) }
    }

    public func delete(account: String, service: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let status = SecItemDelete(query as CFDictionary)
        if status == errSecSuccess || status == errSecItemNotFound { return }
        throw KeychainError.osStatus(status)
    }

    public func deleteAll(service: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
        ]
        let status = SecItemDelete(query as CFDictionary)
        if status == errSecSuccess || status == errSecItemNotFound { return }
        throw KeychainError.osStatus(status)
    }
}

// MARK: - In-Memory Keychain (tests)

public final class InMemoryKeychain: KeychainAccessing, @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [Key: String] = [:]

    public init() {}

    public func read(account: String, service: String) throws -> String? {
        lock.lock(); defer { lock.unlock() }
        return storage[Key(account: account, service: service)]
    }

    public func write(account: String, service: String, value: String) throws {
        lock.lock(); defer { lock.unlock() }
        storage[Key(account: account, service: service)] = value
    }

    public func delete(account: String, service: String) throws {
        lock.lock(); defer { lock.unlock() }
        storage.removeValue(forKey: Key(account: account, service: service))
    }

    public func deleteAll(service: String) throws {
        lock.lock(); defer { lock.unlock() }
        storage = storage.filter { $0.key.service != service }
    }

    public func snapshot() -> [String: String] {
        lock.lock(); defer { lock.unlock() }
        var out: [String: String] = [:]
        for (key, value) in storage {
            out[key.account] = value
        }
        return out
    }

    private struct Key: Hashable, Sendable {
        let account: String
        let service: String
    }
}
