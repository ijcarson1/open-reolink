import Foundation

public protocol CameraClient: Sendable {
    func fetchSnapshot() async throws -> Data
}

public enum CameraClientError: Error, Sendable, Equatable {
    case unauthorized
    case lockedOut
    case unreachable(underlying: String)
    case unexpectedResponse(status: Int)
    case decoding(String)
}
