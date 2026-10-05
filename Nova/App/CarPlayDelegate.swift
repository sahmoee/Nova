#if os(iOS) && canImport(CarPlay)
import CarPlay
import Combine
import UIKit

/// Audio controls for an already-running Nova session. Activation requires an approved
/// CarPlay audio entitlement and a CPTemplateApplicationScene entry in the scene manifest.
/// This adapter never starts video playback or displays video in the car.
@MainActor
final class NovaCarPlaySceneDelegate: UIResponder, CPTemplateApplicationSceneDelegate {
    private weak var interfaceController: CPInterfaceController?
    private var stateObservation: AnyCancellable?
    private var connection = UUID()

    func templateApplicationScene(_ scene: CPTemplateApplicationScene,
                                  didConnect controller: CPInterfaceController) {
        connection = UUID()
        interfaceController = controller
        stateObservation = NowPlayingStore.shared.$current
            .combineLatest(NowPlayingStore.shared.$isPlaying)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] item, playing in
                self?.updateRoot(title: item?.displayTitle, playing: playing)
            }
    }

    func templateApplicationScene(_ scene: CPTemplateApplicationScene,
                                  didDisconnect controller: CPInterfaceController) {
        guard interfaceController === controller else { return }
        connection = UUID()
        stateObservation?.cancel()
        stateObservation = nil
        interfaceController = nil
    }

    private func updateRoot(title: String?, playing: Bool) {
        guard let controller = interfaceController else { return }
        let nowPlaying = CPListItem(text: "Now Playing", detailText: title ?? "Start playback in Nova on your iPhone.")
        nowPlaying.isEnabled = title != nil
        nowPlaying.handler = { [weak self] _, completion in
            guard let self, let current = self.interfaceController else { completion(); return }
            let generation = self.connection
            Task { @MainActor in
                defer { completion() }
                guard generation == self.connection else { return }
                try? await current.pushTemplate(CPNowPlayingTemplate.shared, animated: true)
            }
        }
        let pause = CPListItem(text: "Pause Playback", detailText: playing ? "Pause and save your place." : "Playback is paused.")
        pause.isEnabled = title != nil && playing
        pause.handler = { _, completion in
            PlaybackCoordinator.shared.pauseActive()
            completion()
        }
        let stop = CPListItem(text: "Stop Playback", detailText: "Stop and save your place.")
        stop.isEnabled = title != nil
        stop.handler = { _, completion in
            PlaybackCoordinator.shared.stopAll()
            completion()
        }
        let root = CPListTemplate(title: "Nova", sections: [CPListSection(items: [nowPlaying, pause, stop])])
        let generation = connection
        Task { @MainActor in
            guard generation == self.connection else { return }
            try? await controller.setRootTemplate(root, animated: false)
        }
    }
}
#endif
