import Foundation

public protocol VisionProvider: Sendable {
    var displayName: String { get }
    func analyze(jpeg: Data, prompt: String) async throws -> String
}

public enum VisionProviderError: Error, Sendable, Equatable {
    case unauthorized
    case rateLimited
    case serverError(Int)
    case transport(String)
    case malformedResponse(String)
}

public enum VisionProviderKind: String, Sendable, Codable, CaseIterable {
    case none
    case anthropic
    case openai

    public var displayName: String {
        switch self {
        case .none: return "Off"
        case .anthropic: return "Anthropic Claude"
        case .openai: return "OpenAI"
        }
    }
}
