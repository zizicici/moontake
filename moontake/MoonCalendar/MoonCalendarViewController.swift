import UIKit
import SnapKit
import MoreKit
import CoreImage

final class MoonCalendarViewController: UIViewController {
    private var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: Bundle.main.preferredLocalizations.first ?? "en")
        calendar.timeZone = .current
        calendar.firstWeekday = Calendar.current.firstWeekday
        return calendar
    }()
    private var selectedDate = Date()
    private var displayedMonth = Date()
    private var month: MoonCalendarMonth?
    private var loadTask: Task<Void, Never>?
    private let hasFullCalendarAccess: () -> Bool
    private var dayButtons: [UIButton] = []
    private let scrollView = UIScrollView()
    private let content = UIStackView()
    private let information = UIStackView()
    private let informationContainer = UIView()
    private let lockedOverlay = UIView()
    private let blurredPreview = UIImageView()
    private let blurContext = CIContext()
    private var previewNeedsUpdate = true
    private var previewSize = CGSize.zero
    private let detail = UIStackView()
    private let phaseView = MoonPhaseView()
    private let selectedDateLabel = UILabel()
    private let phaseLabel = UILabel()
    private let illuminationLabel = UILabel()
    private let nextFullMoonLabel = UILabel()
    private let monthLabel = UILabel()
    private let grid = UIStackView()
    private let eventsStack = UIStackView()
    private let statusLabel = UILabel()
    private let spinner = UIActivityIndicatorView(style: .medium)
    private let retryButton = UIButton(type: .system)

    init(date: Date = Date(), calendar: Calendar? = nil,
         hasFullCalendarAccess: @escaping () -> Bool = { User.shared.proTier() != .none }) {
        self.selectedDate = date
        self.displayedMonth = date
        if let calendar { self.calendar = calendar }
        self.hasFullCalendarAccess = hasFullCalendarAccess
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    deinit { loadTask?.cancel() }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = String(localized: "moon_calendar.title")
        view.backgroundColor = .skyColor
        view.tintColor = .moonColor
        let appearance = UINavigationBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = .skyColor
        appearance.titleTextAttributes = [.foregroundColor: UIColor.moonColor]
        appearance.shadowColor = .clear
        navigationItem.standardAppearance = appearance
        navigationItem.scrollEdgeAppearance = appearance
        navigationController?.navigationBar.tintColor = .moonColor
        navigationItem.rightBarButtonItem = UIBarButtonItem(image: UIImage(systemName: "xmark"),
            style: .plain, target: self, action: #selector(close))
        navigationItem.rightBarButtonItem?.accessibilityLabel = String(localized: "tutorials.close")
        navigationItem.rightBarButtonItem?.accessibilityIdentifier = "moonCalendar.close"
        navigationItem.leftBarButtonItem = UIBarButtonItem(title: String(localized: "date.today"),
            style: .plain, target: self, action: #selector(showToday))
        navigationItem.leftBarButtonItem?.accessibilityIdentifier = "moonCalendar.today"

        view.addSubview(scrollView)
        scrollView.alwaysBounceVertical = true
        scrollView.snp.makeConstraints { $0.edges.equalTo(view.safeAreaLayoutGuide) }
        scrollView.contentLayoutGuide.snp.makeConstraints { $0.width.equalTo(scrollView.frameLayoutGuide) }
        content.axis = .vertical
        content.spacing = 22
        scrollView.addSubview(content)
        content.snp.makeConstraints {
            $0.top.bottom.equalTo(scrollView.contentLayoutGuide).inset(20)
            $0.centerX.equalTo(scrollView.frameLayoutGuide)
            $0.width.equalTo(scrollView.frameLayoutGuide).offset(-32).priority(999)
            $0.width.lessThanOrEqualTo(560)
            $0.leading.greaterThanOrEqualTo(scrollView.contentLayoutGuide).inset(16)
            $0.trailing.lessThanOrEqualTo(scrollView.contentLayoutGuide).inset(16)
        }
        buildMonthHeader()
        information.axis = .vertical
        information.spacing = 22
        information.accessibilityIdentifier = "moonCalendar.information"
        content.addArrangedSubview(informationContainer)
        informationContainer.addSubview(information)
        information.snp.makeConstraints { $0.edges.equalToSuperview() }
        buildDetail()
        buildLoadingState()
        grid.axis = .vertical
        grid.spacing = 4
        grid.accessibilityIdentifier = "moonCalendar.grid"
        information.addArrangedSubview(grid)
        eventsStack.axis = .vertical
        eventsStack.spacing = 4
        information.addArrangedSubview(eventsStack)
        buildLockedOverlay()
        NotificationCenter.default.addObserver(self, selector: #selector(refreshDateContext),
            name: UIApplication.significantTimeChangeNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(refreshDateContext),
            name: UIApplication.willEnterForegroundNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(membershipChanged),
            name: .StoreInfoLoaded, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(updateBlurAppearance),
            name: UIAccessibility.reduceTransparencyStatusDidChangeNotification, object: nil)
        loadMonth()
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        if previousTraitCollection?.preferredContentSizeCategory != traitCollection.preferredContentSizeCategory,
           let month {
            buildEvents(month)
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        if !lockedOverlay.isHidden,
           previewNeedsUpdate || previewSize != lockedOverlay.bounds.size {
            updateBlurredPreview()
        }
    }

    private func style(_ label: UILabel, _ textStyle: UIFont.TextStyle, opacity: CGFloat = 1) {
        label.font = .preferredFont(forTextStyle: textStyle)
        label.adjustsFontForContentSizeCategory = true
        label.textColor = .moonColor.withAlphaComponent(opacity)
        label.numberOfLines = 0
    }

    private func buildDetail() {
        style(selectedDateLabel, .subheadline, opacity: 0.7)
        style(phaseLabel, .title1)
        style(illuminationLabel, .subheadline, opacity: 0.85)
        illuminationLabel.accessibilityIdentifier = "moonCalendar.illumination"
        phaseLabel.accessibilityIdentifier = "moonCalendar.phase"
        selectedDateLabel.accessibilityIdentifier = "moonCalendar.selectedDate"
        let labels = UIStackView(arrangedSubviews: [selectedDateLabel, phaseLabel, illuminationLabel])
        labels.axis = .vertical
        labels.spacing = 6
        phaseView.snp.makeConstraints { $0.size.equalTo(80) }
        let hero = UIStackView(arrangedSubviews: [phaseView, labels])
        hero.spacing = 22
        hero.alignment = .center
        detail.axis = .vertical
        detail.spacing = 16
        detail.addArrangedSubview(hero)
        style(nextFullMoonLabel, .subheadline, opacity: 0.85)
        nextFullMoonLabel.accessibilityIdentifier = "moonCalendar.nextFullMoon"
        detail.addArrangedSubview(nextFullMoonLabel)
        information.addArrangedSubview(detail)
    }

    private func buildMonthHeader() {
        style(monthLabel, .title3)
        monthLabel.accessibilityTraits.insert(.header)
        monthLabel.accessibilityIdentifier = "moonCalendar.month"
        let previous = monthButton(symbol: "chevron.backward", key: "moon_calendar.previous_month", id: "previous", offset: -1)
        let next = monthButton(symbol: "chevron.forward", key: "moon_calendar.next_month", id: "next", offset: 1)
        let row = UIStackView(arrangedSubviews: [monthLabel, previous, next])
        row.alignment = .center
        row.spacing = 4
        content.addArrangedSubview(row)
        content.setCustomSpacing(10, after: row)
    }

    private func monthButton(symbol: String, key: String, id: String, offset: Int) -> UIButton {
        let button = UIButton(type: .system)
        button.setImage(UIImage(systemName: symbol), for: .normal)
        button.accessibilityLabel = NSLocalizedString(key, comment: "")
        button.accessibilityIdentifier = "moonCalendar.\(id)"
        button.snp.makeConstraints { $0.size.equalTo(44) }
        button.addAction(UIAction { [weak self] _ in self?.changeMonth(by: offset) }, for: .touchUpInside)
        return button
    }

    private func buildLoadingState() {
        spinner.color = .moonColor
        spinner.hidesWhenStopped = true
        information.addArrangedSubview(spinner)
        style(statusLabel, .subheadline, opacity: 0.8)
        statusLabel.textAlignment = .center
        statusLabel.accessibilityIdentifier = "moonCalendar.status"
        information.addArrangedSubview(statusLabel)
        retryButton.setTitle(String(localized: "moon_calendar.retry"), for: .normal)
        retryButton.addAction(UIAction { [weak self] _ in self?.loadMonth() }, for: .touchUpInside)
        retryButton.snp.makeConstraints { $0.height.greaterThanOrEqualTo(44) }
        information.addArrangedSubview(retryButton)
    }

    private func buildLockedOverlay() {
        lockedOverlay.accessibilityIdentifier = "moonCalendar.lock"
        lockedOverlay.clipsToBounds = true
        lockedOverlay.backgroundColor = .skyColor
        informationContainer.addSubview(lockedOverlay)
        lockedOverlay.snp.makeConstraints {
            $0.top.bottom.equalToSuperview()
            $0.leading.trailing.equalToSuperview().inset(-16)
        }
        lockedOverlay.addSubview(blurredPreview)
        blurredPreview.snp.makeConstraints { $0.edges.equalToSuperview() }
        let message = UILabel()
        style(message, .body)
        message.text = String(localized: "moon_calendar.locked_message")
        message.textAlignment = .center
        message.accessibilityIdentifier = "moonCalendar.lockedMessage"
        let unlock = UIButton(type: .system)
        var configuration = UIButton.Configuration.filled()
        configuration.title = String(localized: "moon_calendar.unlock")
        configuration.baseBackgroundColor = .systemYellow
        configuration.baseForegroundColor = .skyColor
        configuration.cornerStyle = .capsule
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 12, leading: 28, bottom: 12, trailing: 28)
        unlock.configuration = configuration
        unlock.accessibilityIdentifier = "moonCalendar.unlock"
        unlock.addAction(UIAction { [weak self] _ in self?.showMembership() }, for: .touchUpInside)
        unlock.snp.makeConstraints { $0.height.greaterThanOrEqualTo(44) }
        let prompt = UIStackView(arrangedSubviews: [message, unlock])
        prompt.axis = .vertical
        prompt.alignment = .center
        prompt.spacing = 22
        lockedOverlay.addSubview(prompt)
        prompt.snp.makeConstraints {
            $0.centerX.equalToSuperview()
            $0.leading.trailing.equalToSuperview().inset(28)
            // Keep the action visible while scrolling the obscured calendar.
            $0.centerY.equalTo(scrollView.frameLayoutGuide).priority(750)
            $0.top.greaterThanOrEqualToSuperview().inset(32)
            $0.bottom.lessThanOrEqualToSuperview().inset(32)
        }
        updateBlurAppearance()
        updateAccess()
    }

    @objc private func updateBlurAppearance() {
        blurredPreview.isHidden = UIAccessibility.isReduceTransparencyEnabled
        previewNeedsUpdate = true
        view.setNeedsLayout()
    }

    private func updateBlurredPreview() {
        guard !blurredPreview.isHidden, lockedOverlay.bounds.width > 0,
              lockedOverlay.bounds.height > 0 else { return }
        // The calendar is static between selections. Blur its rendered snapshot
        // with a small radius so the layout remains visible without a tinted slab
        // or a continuously running effect animation.
        func displayLayers(in view: UIView) {
            view.layer.displayIfNeeded()
            view.subviews.forEach { displayLayers(in: $0) }
        }
        displayLayers(in: information)
        let format = UIGraphicsImageRendererFormat()
        format.scale = traitCollection.displayScale
        format.opaque = true
        let snapshot = UIGraphicsImageRenderer(size: lockedOverlay.bounds.size, format: format).image { context in
            UIColor.skyColor.setFill()
            context.fill(lockedOverlay.bounds)
            context.cgContext.translateBy(x: 16, y: 0)
            information.layer.render(in: context.cgContext)
        }
        guard let source = CIImage(image: snapshot) else { return }
        let blurred = source.clampedToExtent().applyingGaussianBlur(sigma: 4 * format.scale).cropped(to: source.extent)
        guard let result = blurContext.createCGImage(blurred, from: source.extent) else { return }
        blurredPreview.image = UIImage(cgImage: result, scale: format.scale, orientation: .up)
        previewSize = lockedOverlay.bounds.size
        previewNeedsUpdate = false
    }

    private func updateAccess() {
        // A pending transition back to this month must keep the previous paid
        // snapshot covered until the new current-month snapshot is displayed.
        let isLocked = !canViewMonth(containing: displayedMonth)
            || month.map { !canViewMonth(containing: $0.start) } == true
        lockedOverlay.isHidden = !isLocked
        if isLocked {
            previewNeedsUpdate = true
            view.setNeedsLayout()
        }
        information.isUserInteractionEnabled = !isLocked
        information.accessibilityElementsHidden = isLocked
    }

    private func showMembership() {
        guard presentedViewController == nil else { return }
        present(UINavigationController(rootViewController: makeMorePageViewController()), animated: true)
    }

    private func formatted(_ date: Date, template: String) -> String {
        let formatter = DateFormatter()
        formatter.locale = calendar.locale
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.setLocalizedDateFormatFromTemplate(template)
        return formatter.string(from: date)
    }

    private func loadMonth() {
        loadTask?.cancel()
        updateAccess()
        if month == nil {
            monthLabel.text = formatted(displayedMonth, template: "yMMMM")
            [detail, grid, eventsStack, retryButton].forEach { $0.isHidden = true }
            spinner.isHidden = false
            spinner.startAnimating()
            statusLabel.isHidden = false
            statusLabel.text = String(localized: "moon_calendar.loading")
        }
        // Keep the last complete month on screen until its replacement is ready.
        // Hiding arranged subviews here collapses contentSize and resets scrolling.
        grid.isUserInteractionEnabled = false
        eventsStack.isUserInteractionEnabled = false
        let date = displayedMonth
        let calendar = calendar
        loadTask = Task { [weak self] in
            guard !Task.isCancelled else { return }
            let calculation = Task.detached(priority: .userInitiated) {
                await MoonManager.shared.prepare(at: date)
                if let end = calendar.dateInterval(of: .month, for: date)?.end {
                    await MoonManager.shared.prepare(at: end.addingTimeInterval(40 * 86400))
                }
                guard !Task.isCancelled else { return Optional<MoonCalendarMonth>.none }
                return MoonCalendarMonth.calculate(containing: date, calendar: calendar)
            }
            let result = await withTaskCancellationHandler(operation: {
                await calculation.value
            }, onCancel: { calculation.cancel() })
            guard !Task.isCancelled else { return }
            self?.show(result)
        }
    }

    private func show(_ result: MoonCalendarMonth?) {
        finishLoading()
        guard let result else {
            month = nil
            updateAccess()
            monthLabel.text = formatted(displayedMonth, template: "yMMMM")
            [detail, grid, eventsStack].forEach { $0.isHidden = true }
            statusLabel.text = String(localized: "moon_calendar.unavailable")
            statusLabel.isHidden = false
            retryButton.isHidden = false
            return
        }
        let offset = scrollView.contentOffset
        UIView.performWithoutAnimation {
            month = result
            monthLabel.text = formatted(result.start, template: "yMMMM")
            [detail, grid, eventsStack].forEach { $0.isHidden = false }
            updateNextFullMoon(result)
            buildGrid(result)
            buildEvents(result)
            updateSelection()
            updateAccess()
            view.layoutIfNeeded()
            let top = -scrollView.adjustedContentInset.top
            let bottom = max(top, scrollView.contentSize.height - scrollView.bounds.height + scrollView.adjustedContentInset.bottom)
            scrollView.setContentOffset(CGPoint(x: 0, y: min(max(offset.y, top), bottom)), animated: false)
        }
    }

    private func finishLoading() {
        spinner.stopAnimating()
        spinner.isHidden = true
        statusLabel.isHidden = true
        retryButton.isHidden = true
        grid.isUserInteractionEnabled = true
        eventsStack.isUserInteractionEnabled = true
    }

    private func updateNextFullMoon(_ result: MoonCalendarMonth) {
        // Do not reveal next month's full Moon to users with current-month access.
        nextFullMoonLabel.isHidden = !canViewMonth(containing: result.nextFullMoon)
        nextFullMoonLabel.text = String.localizedStringWithFormat(String(localized: "moon_calendar.next_full"),
            formatted(result.nextFullMoon, template: calendar.isDate(result.nextFullMoon, equalTo: Date(), toGranularity: .year) ? "MMMd" : "MMMdy"), formatted(result.nextFullMoon, template: "jm"))
    }

    private func clear(_ stack: UIStackView) {
        stack.arrangedSubviews.forEach { $0.removeFromSuperview() }
    }

    private func buildGrid(_ month: MoonCalendarMonth) {
        clear(grid)
        dayButtons = []
        let formatter = DateFormatter()
        formatter.locale = calendar.locale
        formatter.calendar = calendar
        let symbols = formatter.veryShortStandaloneWeekdaySymbols ?? formatter.shortWeekdaySymbols!
        let weekdays = UIStackView()
        weekdays.distribution = .fillEqually
        for offset in 0..<7 {
            let label = UILabel()
            style(label, .caption1, opacity: 0.5)
            label.textAlignment = .center
            label.text = symbols[(calendar.firstWeekday - 1 + offset) % 7]
            label.isAccessibilityElement = false
            weekdays.addArrangedSubview(label)
        }
        grid.addArrangedSubview(weekdays)
        grid.setCustomSpacing(8, after: weekdays)
        let daysByCell = Dictionary(uniqueKeysWithValues: month.days.map { ($0.gridIndex, $0) })
        let count = (((month.days.last?.gridIndex ?? 0) + 7) / 7) * 7
        for rowIndex in 0..<(count / 7) {
            let row = UIStackView()
            row.distribution = .fillEqually
            row.spacing = 2
            for column in 0..<7 {
                guard let day = daysByCell[rowIndex * 7 + column] else {
                    row.addArrangedSubview(UIView())
                    continue
                }
                let button = makeDayButton(day)
                row.addArrangedSubview(button)
                dayButtons.append(button)
            }
            grid.addArrangedSubview(row)
        }
    }

    private func makeDayButton(_ day: MoonCalendarMonth.Day) -> UIButton {
        let button = UIButton(type: .custom)
        button.layer.cornerRadius = 12
        button.layer.borderWidth = 1
        button.accessibilityIdentifier = "moonCalendar.day.\(calendar.component(.day, from: day.date))"
        button.accessibilityLabel = [formatted(day.date, template: "MMMEd"), day.name,
            calendar.isDateInToday(day.date) ? String(localized: "date.today") : nil].compactMap { $0 }.joined(separator: ", ")
        let number = UILabel()
        style(number, .caption1, opacity: 0.85)
        let numberFormatter = NumberFormatter()
        numberFormatter.locale = calendar.locale
        number.text = numberFormatter.string(from: NSNumber(value: calendar.component(.day, from: day.date)))
        number.textAlignment = .center
        number.isAccessibilityElement = false
        number.isUserInteractionEnabled = false
        button.addSubview(number)
        number.snp.makeConstraints { $0.top.equalToSuperview().inset(7); $0.centerX.equalToSuperview() }
        let moon = MoonPhaseView()
        moon.angle = day.angle
        button.addSubview(moon)
        moon.snp.makeConstraints {
            $0.top.equalTo(number.snp.bottom).offset(6)
            $0.centerX.equalToSuperview()
            $0.size.equalTo(22)
            $0.bottom.equalToSuperview().inset(13)
        }
        button.addAction(UIAction { [weak self] _ in self?.select(day.date) }, for: .touchUpInside)
        return button
    }

    private func buildEvents(_ month: MoonCalendarMonth) {
        clear(eventsStack)
        let heading = UILabel()
        style(heading, .subheadline, opacity: 0.65)
        heading.text = String(localized: "moon_calendar.events")
        heading.accessibilityTraits.insert(.header)
        eventsStack.addArrangedSubview(heading)
        eventsStack.setCustomSpacing(10, after: heading)
        for event in month.events {
            let button = UIButton(type: .custom)
            let icon = MoonPhaseView()
            icon.angle = event.quarter.rawValue
            icon.snp.makeConstraints { $0.size.equalTo(24) }
            let name = UILabel()
            style(name, .subheadline)
            name.text = event.name
            let time = UILabel()
            style(time, .subheadline, opacity: 0.7)
            time.text = formatted(event.date, template: "MMMdjm")
            time.textAlignment = Language.current().isRightToLeft ? .left : .right
            let labels = UIStackView(arrangedSubviews: [name, time])
            labels.axis = traitCollection.preferredContentSizeCategory.isAccessibilityCategory ? .vertical : .horizontal
            labels.alignment = .center
            labels.spacing = 12
            time.setContentCompressionResistancePriority(.required, for: .horizontal)
            let row = UIStackView(arrangedSubviews: [icon, labels])
            row.spacing = 14
            row.alignment = .center
            row.isUserInteractionEnabled = false
            button.addSubview(row)
            row.snp.makeConstraints { $0.edges.equalToSuperview().inset(10) }
            button.backgroundColor = .moonColor.withAlphaComponent(event.quarter == .fullMoon ? 0.06 : 0)
            button.layer.cornerRadius = 12
            button.accessibilityLabel = [event.name, time.text ?? ""].joined(separator: ", ")
            button.accessibilityIdentifier = "moonCalendar.event.\(calendar.component(.day, from: event.date))"
            button.addAction(UIAction { [weak self] _ in
                self?.select(event.date)
                self?.scrollView.setContentOffset(.zero, animated: true)
            }, for: .touchUpInside)
            eventsStack.addArrangedSubview(button)
        }
    }

    private func select(_ date: Date) {
        guard canViewMonth(containing: date) else { return }
        selectedDate = date
        updateSelection()
    }

    private func updateSelection() {
        guard let month,
              let selected = month.days.first(where: { calendar.isDate($0.date, inSameDayAs: selectedDate) })
                ?? month.days.first else { return }
        selectedDate = selected.date
        selectedDateLabel.text = formatted(selected.date, template: "MMMEd")
        phaseView.angle = selected.angle
        phaseLabel.text = selected.name
        illuminationLabel.text = Self.illuminationText(selected.illuminationChange, locale: calendar.locale ?? .current)
        for (index, button) in dayButtons.enumerated() {
            let isSelected = calendar.isDate(month.days[index].date, inSameDayAs: selectedDate)
            button.backgroundColor = .moonColor.withAlphaComponent(isSelected ? 0.14 : 0)
            let isToday = calendar.isDateInToday(month.days[index].date)
            button.layer.borderColor = UIColor.moonColor.withAlphaComponent(isSelected ? 0.65 : (isToday ? 0.25 : 0)).cgColor
            button.accessibilityTraits = isSelected ? [.button, .selected] : [.button]
        }
    }

    static func illuminationText(_ change: MoonManager.IlluminationChange, locale: Locale) -> String {
        let percent = NumberFormatter()
        percent.locale = locale
        percent.numberStyle = .percent
        percent.minimumFractionDigits = 1
        percent.maximumFractionDigits = 1
        return String.localizedStringWithFormat(String(localized: "moon_calendar.illumination_change"),
            percent.string(from: NSNumber(value: change.start)) ?? "—",
            percent.string(from: NSNumber(value: change.end)) ?? "—")
    }

    private func changeMonth(by offset: Int) {
        guard let start = calendar.dateInterval(of: .month, for: displayedMonth)?.start,
              let next = calendar.date(byAdding: .month, value: offset, to: start) else { return }
        displayedMonth = next
        selectedDate = calendar.isDate(next, equalTo: Date(), toGranularity: .month) ? Date() : next
        loadMonth()
    }

    @objc private func showToday() {
        selectedDate = Date()
        displayedMonth = selectedDate
        loadTask?.cancel()
        if let month, month.timeZone == calendar.timeZone,
           calendar.isDate(month.start, equalTo: selectedDate, toGranularity: .month),
           month.nextFullMoon > selectedDate {
            UIView.performWithoutAnimation {
                finishLoading()
                updateSelection()
                updateAccess()
                view.layoutIfNeeded()
            }
        } else {
            loadMonth()
        }
        scrollView.setContentOffset(CGPoint(x: 0, y: -scrollView.adjustedContentInset.top), animated: false)
    }

    private func canViewMonth(containing date: Date) -> Bool {
        hasFullCalendarAccess() || calendar.isDate(date, equalTo: Date(), toGranularity: .month)
    }

    @objc private func membershipChanged() {
        updateAccess()
        if let month {
            updateNextFullMoon(month)
        }
    }

    @objc private func refreshDateContext() {
        refreshCalendar(timeZone: .current)
    }

    func refreshCalendar(timeZone: TimeZone) {
        if calendar.timeZone != timeZone {
            var monthComponents = calendar.dateComponents([.era, .year, .month], from: displayedMonth)
            monthComponents.day = 1
            monthComponents.hour = 12
            var dayComponents = calendar.dateComponents([.era, .year, .month, .day], from: selectedDate)
            dayComponents.hour = 12
            calendar.timeZone = timeZone
            // Preserve civil dates instead of reinterpreting the old zone's
            // absolute midnight, which can fall in the preceding month.
            displayedMonth = calendar.date(from: monthComponents) ?? Date()
            let selection = calendar.date(from: dayComponents) ?? displayedMonth
            selectedDate = calendar.isDate(selection, equalTo: displayedMonth, toGranularity: .month)
                ? selection : displayedMonth
        }
        loadMonth()
    }

    @objc private func close() { dismiss(animated: true) }
}
