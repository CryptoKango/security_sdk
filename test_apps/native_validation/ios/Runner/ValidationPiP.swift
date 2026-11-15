#if DEBUG
import AVFoundation
import AVKit
import UIKit

/// Offline synthetic video fixture. No media/network permission or SDK dependency.
final class ValidationPiP: NSObject, AVPictureInPictureControllerDelegate {
  private weak var view: UIView?
  private var controller: AVPictureInPictureController?
  private var player: AVQueuePlayer?
  private var looper: AVPlayerLooper?
  private var layer: AVPlayerLayer?
  private var file: URL?
  private var phase = "new"
  private var starts = 0
  private var stops = 0
  private var disposed = false
  private var originalAudio: (AVAudioSession.Category, AVAudioSession.Mode, AVAudioSession.CategoryOptions)?
  init(view: UIView) { self.view = view }
  var state: [String: Any] {
    ["phase": phase, "supported": AVPictureInPictureController.isPictureInPictureSupported(),
     "possible": controller?.isPictureInPicturePossible == true,
     "active": controller?.isPictureInPictureActive == true, "starts": starts, "stops": stops]
  }
  func prepare() {
    guard AVPictureInPictureController.isPictureInPictureSupported() else { phase = "unsupported"; return }
    phase = "preparing"
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("security-pip-\(UUID().uuidString).mov")
    file = url
    DispatchQueue.global(qos: .userInitiated).async { [weak self] in
      Self.makeClip(url: url) { success in
        DispatchQueue.main.async { [weak self] in
          guard let self = self, !self.disposed else { try? FileManager.default.removeItem(at: url); return }
          guard success, let view = self.view else { self.phase = "prepareFailed"; return }
          do {
            let audio = AVAudioSession.sharedInstance()
            self.originalAudio = (audio.category, audio.mode, audio.categoryOptions)
            try audio.setCategory(.playback, mode: .moviePlayback, options: .mixWithOthers)
            try audio.setActive(true)
            let player = AVQueuePlayer(); self.player = player
            self.looper = AVPlayerLooper(player: player, templateItem: AVPlayerItem(url: url))
            let layer = AVPlayerLayer(player: player); self.layer = layer
            layer.frame = CGRect(x: 16, y: 80, width: 320, height: 180)
            view.layer.addSublayer(layer)
            self.controller = AVPictureInPictureController(playerLayer: layer)
            self.controller?.delegate = self
            if #available(iOS 14.2, *) { self.controller?.canStartPictureInPictureAutomaticallyFromInline = false }
            player.play(); self.phase = "prepared"
          } catch { self.phase = "prepareFailed" }
        }
      }
    }
  }
  func start() {
    guard controller?.isPictureInPicturePossible == true else { phase = "notPossible"; return }
    phase = "starting"; controller?.startPictureInPicture()
  }
  func stop() { controller?.stopPictureInPicture() }
  func pictureInPictureControllerDidStartPictureInPicture(_ controller: AVPictureInPictureController) { starts += 1; phase = "active" }
  func pictureInPictureControllerDidStopPictureInPicture(_ controller: AVPictureInPictureController) { stops += 1; phase = "stopped" }
  func pictureInPictureController(_ controller: AVPictureInPictureController, failedToStartPictureInPictureWithError error: Error) { phase = "startRejected" }
  func dispose() {
    guard !disposed else { return }; disposed = true
    controller?.stopPictureInPicture(); controller?.delegate = nil; controller = nil
    player?.pause(); looper?.disableLooping(); looper = nil; player = nil
    layer?.removeFromSuperlayer(); layer = nil
    if let file = file { try? FileManager.default.removeItem(at: file) }; file = nil
    if let original = originalAudio {
      let audio = AVAudioSession.sharedInstance()
      try? audio.setActive(false, options: .notifyOthersOnDeactivation)
      try? audio.setCategory(original.0, mode: original.1, options: original.2)
    }
    originalAudio = nil; phase = "disposed"
  }
  deinit { dispose() }

  private static func makeClip(url: URL, done: @escaping (Bool) -> Void) {
    do {
      let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
      let input = AVAssetWriterInput(mediaType: .video, outputSettings: [AVVideoCodecKey: AVVideoCodecType.h264,
        AVVideoWidthKey: 320, AVVideoHeightKey: 180])
      let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
        kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB,
        kCVPixelBufferWidthKey as String: 320, kCVPixelBufferHeightKey as String: 180])
      guard writer.canAdd(input) else { done(false); return }; writer.add(input)
      guard writer.startWriting() else { done(false); return }; writer.startSession(atSourceTime: .zero)
      let queue = DispatchQueue(label: "security.validation.clip"); var frame = 0; var finished = false
      input.requestMediaDataWhenReady(on: queue) {
        guard !finished else { return }
        while input.isReadyForMoreMediaData && frame < 90 {
          var buffer: CVPixelBuffer?
          guard let pool = adaptor.pixelBufferPool,
            CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer) == kCVReturnSuccess, let buffer = buffer else {
            finished = true; writer.cancelWriting(); done(false); return
          }
          CVPixelBufferLockBaseAddress(buffer, [])
          if let address = CVPixelBufferGetBaseAddress(buffer) { memset(address, Int32(40 + frame % 150), CVPixelBufferGetDataSize(buffer)) }
          CVPixelBufferUnlockBaseAddress(buffer, [])
          guard adaptor.append(buffer, withPresentationTime: CMTime(value: Int64(frame), timescale: 30)) else {
            finished = true; writer.cancelWriting(); done(false); return
          }
          frame += 1
        }
        if frame == 90 {
          finished = true; input.markAsFinished(); writer.finishWriting { done(writer.status == .completed) }
        }
      }
      queue.asyncAfter(deadline: .now() + 15) {
        if !finished { finished = true; writer.cancelWriting(); done(false) }
      }
    } catch { done(false) }
  }
}
#endif
