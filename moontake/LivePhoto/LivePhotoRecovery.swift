import UIKit

@MainActor
enum LivePhotoRecovery {
  // Disk-full captures cannot survive termination, but survive dismissals or
  // background transitions in this process until retried or explicitly discarded.
  private static var unstaged: [UUID: LivePhotoStagingFailure] = [:]

  static func offer(
    in controller: UIViewController, showEmpty: Bool = false,
    canPresent: @escaping () -> Bool = { true }
  ) {
    Task { @MainActor [weak controller] in
      let jobs = await LivePhotoSaveService.shared.pending()
      guard let controller, canPresent(), canShow(in: controller) else { return }
      if let failure = unstaged.values.first {
        present(error: failure, in: controller)
      } else if let job = jobs.first {
        present(job, in: controller)
      } else if showEmpty {
        let alert = UIAlertController(
          title: String(localized: "live_photo.recovery.title"),
          message: String(localized: "live_photo.recovery.empty"), preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: String(localized: "action.ok"), style: .default))
        controller.present(alert, animated: true)
      }
    }
  }

  static func present(error: Error, in controller: UIViewController) {
    if let failure = error as? LivePhotoStagingFailure { unstaged[failure.id] = failure }
    Task { @MainActor [weak controller] in
      let failure = error as? LivePhotoSaveFailure
      let job = await LivePhotoSaveService.shared.pending().first { $0.id == failure?.jobID }
      guard let controller, canShow(in: controller) else { return }
      if let failure = error as? LivePhotoStagingFailure {
        let alert = UIAlertController(
          title: String(localized: "live_photo.error_title"),
          message: failure.localizedDescription + "\n\n" + failure.underlying.localizedDescription,
          preferredStyle: .alert)
        alert.addAction(
          UIAlertAction(
            title: String(localized: "live_photo.recovery.discard"), style: .destructive
          ) { _ in
            unstaged[failure.id] = nil
          })
        alert.addAction(
          UIAlertAction(title: String(localized: "live_photo.recovery.retry"), style: .default) {
            [weak controller, weak alert] _ in
            guard let controller else { return }
            alert?.dismiss(animated: true) {
              run(in: controller) {
                try await withCheckedThrowingContinuation { continuation in
                  failure.retry {
                    unstaged[failure.id] = nil
                    continuation.resume(with: $0)
                  }
                }
              }
            }
          })
        controller.present(alert, animated: true)
      } else if let job {
        present(job, in: controller, error: failure?.underlying)
      } else {
        let alert = UIAlertController(
          title: String(localized: "live_photo.error_title"),
          message: error.localizedDescription, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: String(localized: "action.ok"), style: .default))
        controller.present(alert, animated: true)
      }
    }
  }

  private static func canShow(in controller: UIViewController) -> Bool {
    UIApplication.shared.applicationState == .active && controller.viewIfLoaded?.window != nil
      && controller.presentedViewController == nil && !controller.isBeingDismissed
  }

  private static func present(
    _ job: LivePhotoSaveJob, in controller: UIViewController, error: Error? = nil
  ) {
    let message =
      job.phase == .saving
      ? String(localized: "live_photo.recovery.uncertain")
      : String(localized: "live_photo.retained")
    let reason =
      (error != nil && !(error is CancellationError)) ? "\n\n" + error!.localizedDescription : ""
    let alert = UIAlertController(
      title: String(localized: "live_photo.recovery.title"),
      message: job.date.formatted(date: .numeric, time: .standard) + "\n" + message + reason,
      preferredStyle: .alert)
    alert.view.accessibilityIdentifier = "livePhoto.recovery." + job.id.uuidString
    alert.addAction(
      UIAlertAction(title: String(localized: "live_photo.recovery.later"), style: .cancel))
    alert.addAction(
      UIAlertAction(title: String(localized: "live_photo.recovery.retry"), style: .default) {
        [weak controller, weak alert] _ in
        guard let controller else { return }
        // The action sheet finishes dismissing before showing progress.
        alert?.dismiss(animated: true) { retry(job, in: controller) }
      })
    controller.present(alert, animated: true)
  }

  private static func retry(_ job: LivePhotoSaveJob, in controller: UIViewController) {
    run(in: controller) {
      let background = LivePhotoBackgroundTask()
      defer { background.end() }
      try await LivePhotoSaveService.shared.retry(job.id, cancellation: background.cancellation)
    }
  }

  private static func run(
    in controller: UIViewController, operation: @escaping () async throws -> Void
  ) {
    let progress = UIAlertController(
      title: String(localized: "live_photo.recovery.saving"),
      message: nil, preferredStyle: .alert)
    controller.present(progress, animated: true) {
      Task { @MainActor [weak controller] in
        let result: Result<Void, Error>
        do {
          try await operation()
          result = .success(())
        } catch {
          if let failure = error as? LivePhotoStagingFailure { unstaged[failure.id] = failure }
          result = .failure(error)
        }
        progress.dismiss(animated: true) {
          guard let controller else { return }
          switch result {
          case .success: offer(in: controller)
          case .failure(let error): present(error: error, in: controller)
          }
        }
      }
    }
  }
}
