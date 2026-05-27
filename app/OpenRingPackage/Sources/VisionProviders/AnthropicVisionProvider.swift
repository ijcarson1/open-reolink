import Foundation

public final class AnthropicVisionProvider: VisionProvider, @unchecked Sendable {
    public let displayName = "Anthropic Claude"

    private let apiKey: String
    private let model: String
    private let session: URLSession
    private let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!

    public init(apiKey: String, model: String = "claude-sonnet-4-5", session: URLSession = .shared) {
        self.apiKey = apiKey
        self.model = model
        self.session = session
    }

    public func analyze(jpeg: Data, prompt: String) async throws -> String {
        let payload: [String: Any] = [
            "model": model,
            "max_tokens": 256,
            "messages": [[
                "role": "user",
                "content": [
                    [
                        "type": "image",
                        "source": [
                            "type": "base64",
                            "media_type": "image/jpeg",
                            "data": jpeg.base64EncodedString(),
                        ],
                    ],
                    [
                        "type": "text",
                        "text": prompt,
                    ],
                ],
            ]],
        ]

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw VisionProviderError.transport(String(describing: error))
        }

        guard let http = response as? HTTPURLResponse else {
            throw VisionProviderError.transport("non-HTTP response")
        }
        switch http.statusCode {
        case 200:
            return try Self.extractText(from: data)
        case 401:
            throw VisionProviderError.unauthorized
        case 429:
            throw VisionProviderError.rateLimited
        default:
            throw VisionProviderError.serverError(http.statusCode)
        }
    }

    static func extractText(from data: Data) throws -> String {
        guard
            let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let content = root["content"] as? [[String: Any]]
        else {
            throw VisionProviderError.malformedResponse("missing content array")
        }
        let text = content.compactMap { block -> String? in
            guard let type = block["type"] as? String, type == "text" else { return nil }
            return block["text"] as? String
        }
        if text.isEmpty {
            throw VisionProviderError.malformedResponse("no text blocks in response")
        }
        return text.joined(separator: "\n")
    }
}
