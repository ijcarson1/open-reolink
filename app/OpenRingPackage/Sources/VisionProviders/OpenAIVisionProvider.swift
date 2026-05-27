import Foundation

public final class OpenAIVisionProvider: VisionProvider, @unchecked Sendable {
    public let displayName = "OpenAI"

    private let apiKey: String
    private let model: String
    private let session: URLSession
    private let endpoint = URL(string: "https://api.openai.com/v1/chat/completions")!

    public init(apiKey: String, model: String = "gpt-4o", session: URLSession = .shared) {
        self.apiKey = apiKey
        self.model = model
        self.session = session
    }

    public func analyze(jpeg: Data, prompt: String) async throws -> String {
        let dataURL = "data:image/jpeg;base64,\(jpeg.base64EncodedString())"
        let payload: [String: Any] = [
            "model": model,
            "max_tokens": 256,
            "messages": [[
                "role": "user",
                "content": [
                    [
                        "type": "image_url",
                        "image_url": ["url": dataURL],
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
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
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
            let choices = root["choices"] as? [[String: Any]],
            let first = choices.first,
            let message = first["message"] as? [String: Any],
            let content = message["content"] as? String
        else {
            throw VisionProviderError.malformedResponse("missing choices[0].message.content")
        }
        return content
    }
}
