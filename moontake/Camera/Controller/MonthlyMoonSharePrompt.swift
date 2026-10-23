import Foundation

/// Offers the first recognizable lunar capture each calendar month. Only an
/// actual presentation consumes that month's opportunity.
@MainActor
final class MonthlyMoonSharePrompt {
    typealias Assessment = (Data, Date, Double?, Double?) async -> Bool
    private static let shownKey = "camera.recognizableMoonShareMonths"
    private let defaults: UserDefaults
    private let assess: Assessment
    private let isEnabled: () -> Bool
    private let timeZone: TimeZone
    private var revision = 0
    private var operation: Task<Void, Never>?
    private var queuedPhoto: CapturedPhoto?
    private var pendingMonth: String?
    private(set) var pendingPhoto: CapturedPhoto?
    var onReady: (() -> Void)?

    init(defaults: UserDefaults = .standard, timeZone: TimeZone = .autoupdatingCurrent,
         isEnabled: @escaping () -> Bool = { Settings.shared.getMonthlyShareSettings() == .enable },
         assess: @escaping Assessment = { data, date, latitude, longitude in
        (try? await MoonAtlasEngine().hasRecognizableMaria(
            in: data, at: date, latitude: latitude, longitude: longitude)) == true
    }) {
        self.defaults = defaults
        self.assess = assess
        self.timeZone = timeZone
        self.isEnabled = isEnabled
    }

    deinit { operation?.cancel() }

    func hasPresented(in date: Date) -> Bool { shownMonths.contains(monthKey(date)) }
    private var shownMonths: Set<String> { Set(defaults.stringArray(forKey: Self.shownKey) ?? []) }

    private func monthKey(_ date: Date) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let parts = calendar.dateComponents([.year, .month], from: date)
        return "\(parts.year ?? 0)-\(parts.month ?? 0)"
    }

    func refreshPreferences() {
        guard !isEnabled() else { return }
        discardPreviousCapture()
    }

    /// A new shutter supersedes both a ready candidate and any ongoing check.
    /// Do this before capture completes, even if the new capture later fails.
    func discardPreviousCapture() {
        revision += 1
        queuedPhoto = nil; pendingPhoto = nil; pendingMonth = nil
        // Let an in-flight bounded calculation finish; repeated toggles must not
        // launch overlapping registrations or retain more captures.
    }

    func consider(_ photo: CapturedPhoto) {
        // Also replace a candidate at delivery: the next photo must be assessed
        // itself, never serve as a trigger to present an earlier photo.
        discardPreviousCapture()
        guard isEnabled(), !hasPresented(in: photo.date) else { return }
        // Slow analysis never stalls the shutter or accumulates full-size captures.
        // Keep at most one running capture and the latest waiting capture.
        guard operation == nil else { queuedPhoto = photo; return }
        let assess = assess
        let revision = revision
        let month = monthKey(photo.date)
        operation = Task(priority: .utility) { [weak self] in
            let qualifies = await assess(photo.data, photo.date,
                photo.location?.coordinate.latitude, photo.location?.coordinate.longitude)
            guard !Task.isCancelled, let self else { return }
            self.operation = nil
            if qualifies, self.isEnabled(), revision == self.revision, !self.shownMonths.contains(month) {
                self.pendingPhoto = photo
                self.pendingMonth = month
                self.queuedPhoto = nil
                self.onReady?()
            } else if let next = self.queuedPhoto {
                self.queuedPhoto = nil
                self.consider(next)
            }
        }
    }

    func markPresented() {
        guard let month = pendingMonth else { return }
        defaults.set(shownMonths.union([month]).sorted(), forKey: Self.shownKey)
        pendingPhoto = nil
        pendingMonth = nil
        queuedPhoto = nil
    }
}
