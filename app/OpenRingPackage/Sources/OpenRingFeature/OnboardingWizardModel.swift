import Foundation
import Combine
import ReolinkClient

/// Pluggable wrapper around `NSWorkspace.open(_:)` so the help-button path
/// is unit-testable.
public protocol HelpURLOpening: Sendable {
    func open(_ url: URL)
}

public struct DefaultHelpOpener: HelpURLOpening {
    public init() {}
    public func open(_ url: URL) {
        #if canImport(AppKit)
        Task { @MainActor in
            _ = AppKit.NSWorkspace.shared.open(url)
        }
        #endif
    }
}

#if canImport(AppKit)
import AppKit
#endif

@MainActor
public final class OnboardingWizardModel: ObservableObject {
    public enum Step: Equatable {
        case searching
        case results([DiscoveredCamera])
        case noResults
        case credentials(DiscoveredCamera)
        case manual
    }

    @Published public private(set) var step: Step = .searching

    public let discoveryTimeout: TimeInterval
    public let setupGuideURL: URL

    private let discovery: ONVIFDiscovering
    private let opener: HelpURLOpening

    public init(
        discovery: ONVIFDiscovering = NetworkONVIFDiscovery(),
        opener: HelpURLOpening = DefaultHelpOpener(),
        discoveryTimeout: TimeInterval = 5,
        setupGuideURL: URL = URL(string: "https://github.com/ijcarson1/open-reolink/blob/main/docs/reolink-setup-guide.md")!
    ) {
        self.discovery = discovery
        self.opener = opener
        self.discoveryTimeout = discoveryTimeout
        self.setupGuideURL = setupGuideURL
    }

    public func start() async {
        step = .searching
        do {
            let results = try await discovery.probe(timeout: discoveryTimeout)
            if results.isEmpty {
                step = .noResults
            } else {
                step = .results(results)
            }
        } catch {
            step = .noResults
        }
    }

    public func select(_ camera: DiscoveredCamera) {
        step = .credentials(camera)
    }

    public func switchToManual() {
        step = .manual
    }

    public func openSetupGuide() {
        opener.open(setupGuideURL)
    }
}
