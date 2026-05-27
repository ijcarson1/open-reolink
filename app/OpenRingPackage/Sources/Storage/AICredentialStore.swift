import Foundation

/// AI-provider Keychain wrapper.
///
/// Per ADR-0007 the layout is:
///   - service: `dev.open-reolink`
///   - account: `ai.anthropic`
///   - account: `ai.openai`
///
/// Switching the active provider in settings does NOT delete the inactive
/// provider's key (the user may switch back). Tests use `InMemoryKeychain`.
public final class AICredentialStore: Sendable {
    public enum Provider: String, Sendable {
        case anthropic = "ai.anthropic"
        case openai = "ai.openai"
    }

    private let keychain: KeychainAccessing
    private let service: String

    public init(keychain: KeychainAccessing = SystemKeychain(), service: String = CredentialStore.defaultService) {
        self.keychain = keychain
        self.service = service
    }

    public func apiKey(for provider: Provider) throws -> String? {
        try keychain.read(account: provider.rawValue, service: service)
    }

    public func setAPIKey(_ key: String, for provider: Provider) throws {
        try keychain.write(account: provider.rawValue, service: service, value: key)
    }

    public func deleteAPIKey(for provider: Provider) throws {
        try keychain.delete(account: provider.rawValue, service: service)
    }
}
