import UIKit

/// Shared by the capture delegate and the exporter. Expiration stops expensive
/// work, but never removes the durable originals or guesses whether Photos saved.
final class LivePhotoCancellation: @unchecked Sendable {
  private let lock = NSLock()
  private var cancelled = false
  private var handler: (() -> Void)?

  func check() throws {
    lock.lock()
    let value = cancelled
    lock.unlock()
    if value { throw CancellationError() }
  }

  func cancel() {
    lock.lock()
    cancelled = true
    let callback = handler
    handler = nil
    lock.unlock()
    callback?()
  }

  func onCancel(_ callback: (() -> Void)?) {
    lock.lock()
    let value = cancelled
    handler = value ? nil : callback
    lock.unlock()
    if value { callback?() }
  }
}

final class LivePhotoBackgroundTask {
  let cancellation = LivePhotoCancellation()
  private let lock = NSLock()
  private var identifier = UIBackgroundTaskIdentifier.invalid
  private var ended = false
  private let endTask: (UIBackgroundTaskIdentifier) -> Void

  @MainActor convenience init() {
    let application = UIApplication.shared
    self.init(
      begin: {
        application.beginBackgroundTask(withName: "Save Live Photo", expirationHandler: $0)
      },
      end: { application.endBackgroundTask($0) })
  }

  // Injection also verifies expiration-before-registration and exactly-once cleanup.
  init(
    begin: (@escaping () -> Void) -> UIBackgroundTaskIdentifier,
    end: @escaping (UIBackgroundTaskIdentifier) -> Void
  ) {
    endTask = end
    let id = begin { [weak self] in
      self?.cancellation.cancel()
      self?.end()
    }
    lock.lock()
    let alreadyEnded = ended
    if !alreadyEnded { identifier = id }
    lock.unlock()
    if alreadyEnded, id != .invalid { end(id) }
    if id == .invalid { cancellation.cancel() }
  }

  func end() {
    lock.lock()
    ended = true
    let id = identifier
    identifier = .invalid
    lock.unlock()
    if id != .invalid { endTask(id) }
  }

  deinit { end() }
}

/// UIKit's finite background assertion covers file/Photos work, not new Metal
/// commands. Stop the GPU conversion before the app leaves the foreground; the
/// durable job can restart without publishing partially rendered frames.
@MainActor
final class LivePhotoForegroundGuard {
  private var observers: [NSObjectProtocol] = []
  private let center: NotificationCenter

  init(
    cancellation: LivePhotoCancellation, center: NotificationCenter = .default,
    isBackground: Bool? = nil
  ) {
    self.center = center
    for name in [
      UIApplication.willResignActiveNotification, UIApplication.didEnterBackgroundNotification,
    ] {
      observers.append(
        center.addObserver(forName: name, object: nil, queue: .main) { _ in cancellation.cancel() })
    }
    if isBackground ?? (UIApplication.shared.applicationState == .background) {
      cancellation.cancel()
    }
  }

  deinit { for observer in observers { center.removeObserver(observer) } }
}
