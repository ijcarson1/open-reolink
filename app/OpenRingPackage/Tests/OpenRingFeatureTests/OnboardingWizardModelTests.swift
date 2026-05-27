import Foundation
import Testing
import ReolinkClient
@testable import OpenRingFeature

@Suite("OnboardingWizardModel")
@MainActor
struct OnboardingWizardModelTests {

    @Test("Successful discovery transitions to .results with the entries")
    func resultsStep() async {
        let model = OnboardingWizardModel(
            discovery: FakeDiscovery(result: [
                DiscoveredCamera(ip: "192.0.2.10", manufacturer: "Reolink", model: "Duo 3 PoE")
            ]),
            opener: StubOpener(),
            discoveryTimeout: 0.1
        )
        await model.start()
        if case .results(let entries) = model.step {
            #expect(entries.count == 1)
            #expect(entries.first?.ip == "192.0.2.10")
        } else {
            Issue.record("expected .results, got \(model.step)")
        }
    }

    @Test("Empty discovery transitions to .noResults (manual fallback)")
    func noResultsFallback() async {
        let model = OnboardingWizardModel(
            discovery: FakeDiscovery(result: []),
            opener: StubOpener(),
            discoveryTimeout: 0.1
        )
        await model.start()
        #expect(model.step == .noResults)
    }

    @Test("Discovery error also falls back to .noResults")
    func errorFallback() async {
        let model = OnboardingWizardModel(
            discovery: FakeDiscovery(error: NSError(domain: "test", code: 1)),
            opener: StubOpener(),
            discoveryTimeout: 0.1
        )
        await model.start()
        #expect(model.step == .noResults)
    }

    @Test("select(camera) moves to credentials step")
    func selectCamera() {
        let model = OnboardingWizardModel(discovery: FakeDiscovery(result: []), opener: StubOpener())
        let camera = DiscoveredCamera(ip: "192.0.2.10", manufacturer: "Reolink")
        model.select(camera)
        if case .credentials(let selected) = model.step {
            #expect(selected.ip == "192.0.2.10")
        } else {
            Issue.record("expected .credentials, got \(model.step)")
        }
    }

    @Test("switchToManual moves to manual step")
    func manualSwitch() {
        let model = OnboardingWizardModel(discovery: FakeDiscovery(result: []), opener: StubOpener())
        model.switchToManual()
        #expect(model.step == .manual)
    }

    @Test("Help button opens the configured setup-guide URL via the opener")
    func helpOpensSetupGuide() {
        let opener = StubOpener()
        let model = OnboardingWizardModel(
            discovery: FakeDiscovery(result: []),
            opener: opener,
            setupGuideURL: URL(string: "https://example.com/setup")!
        )
        model.openSetupGuide()
        #expect(opener.opened == [URL(string: "https://example.com/setup")!])
    }

    @Test("Prefilling the AddCameraForm from a discovered camera sets IP, default name, model, and source")
    func prefill() {
        let formModel = AddCameraFormModel()
        let discovered = DiscoveredCamera(
            ip: "192.0.2.10",
            manufacturer: "Reolink",
            model: "Duo 3 PoE"
        )
        formModel.prefill(from: discovered)
        #expect(formModel.lanIP == "192.0.2.10")
        #expect(formModel.displayName == "Duo 3 PoE")
        #expect(formModel.discoveredVia == .onvifDiscovery)
        #expect(formModel.discoveredModel == "Duo 3 PoE")
    }
}

private struct FakeDiscovery: ONVIFDiscovering {
    let result: [DiscoveredCamera]
    let error: Error?

    init(result: [DiscoveredCamera] = [], error: Error? = nil) {
        self.result = result
        self.error = error
    }

    func probe(timeout: TimeInterval) async throws -> [DiscoveredCamera] {
        if let error { throw error }
        return result
    }
}

private final class StubOpener: HelpURLOpening, @unchecked Sendable {
    private let lock = NSLock()
    private var _opened: [URL] = []
    var opened: [URL] {
        lock.lock(); defer { lock.unlock() }
        return _opened
    }
    func open(_ url: URL) {
        lock.lock(); defer { lock.unlock() }
        _opened.append(url)
    }
}
