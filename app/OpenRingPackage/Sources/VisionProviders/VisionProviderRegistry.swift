import Foundation

/// Reads the active provider + API key and returns a `VisionProvider`, or
/// `nil` when AI is off. Slice 7 will hook this up to live settings
/// updates; for now the resolver is constructed per-event.
public struct VisionProviderRegistry: Sendable {
    public let activeKind: VisionProviderKind
    public let anthropicKey: String?
    public let openAIKey: String?
    public let anthropicModel: String
    public let openAIModel: String

    public init(
        activeKind: VisionProviderKind,
        anthropicKey: String?,
        openAIKey: String?,
        anthropicModel: String = "claude-sonnet-4-5",
        openAIModel: String = "gpt-4o"
    ) {
        self.activeKind = activeKind
        self.anthropicKey = anthropicKey
        self.openAIKey = openAIKey
        self.anthropicModel = anthropicModel
        self.openAIModel = openAIModel
    }

    public func resolve() -> VisionProvider? {
        switch activeKind {
        case .none:
            return nil
        case .anthropic:
            guard let key = anthropicKey, !key.isEmpty else { return nil }
            return AnthropicVisionProvider(apiKey: key, model: anthropicModel)
        case .openai:
            guard let key = openAIKey, !key.isEmpty else { return nil }
            return OpenAIVisionProvider(apiKey: key, model: openAIModel)
        }
    }
}
