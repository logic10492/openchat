import Darwin
import UIKit

final class ChatTimelineViewController: UIViewController {
    private let collectionView: UICollectionView
    private var timelineDataSource: ChatTimelineDataSource!
    private var configuration: ChatTimelineConfiguration
    private var items: [ChatTimelineItem] = []
    private var didPerformInitialScroll = false
    private var shouldFollowStreaming = true
    private var isApplyingPrepend = false
    private var previousContentHeight: CGFloat = 0
    private var previousContentOffsetY: CGFloat = 0
    private var scheduledStreamingScroll: DispatchWorkItem?
    private var resumeFollowWorkItem: DispatchWorkItem?
    private var scrollIdleWorkItem: DispatchWorkItem?
    private var isReportingScrolling = false
    private var suppressScrollReportingUntil: CFTimeInterval = 0
    private var lastScrollIdleScheduleTime: CFTimeInterval = 0
    private var lastCollectionBoundsSize: CGSize = .zero
    #if DEBUG
    private var performanceAutoScrollProbe: ChatTimelineAutoScrollProbe?
    #endif

    init(configuration: ChatTimelineConfiguration) {
        self.configuration = configuration
        collectionView = UICollectionView(frame: .zero, collectionViewLayout: ChatTimelineLayout.makeCollectionViewLayout())
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        #if DEBUG
        performanceAutoScrollProbe?.stop()
        #endif
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        configureCollectionView()
        timelineDataSource = ChatTimelineDataSource(collectionView: collectionView, configuration: configuration)
        apply(configuration, animated: false)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        invalidateLayoutAfterBoundsChangeIfNeeded()
        guard !didPerformInitialScroll else { return }
        scrollToBottom(animated: false)
        didPerformInitialScroll = true
        startPerformanceAutoScrollIfNeeded()
    }

    func update(_ configuration: ChatTimelineConfiguration) {
        let oldConfiguration = self.configuration
        self.configuration = configuration
        timelineDataSource.updateConfiguration(configuration)
        let isPrepending = isPrependingMessages(old: oldConfiguration.messages, new: configuration.messages)
        isApplyingPrepend = isPrepending
        if isApplyingPrepend {
            previousContentHeight = collectionView.collectionViewLayout.collectionViewContentSize.height
            previousContentOffsetY = collectionView.contentOffset.y
        }
        apply(configuration, animated: oldConfiguration.messages.count != 0) { [weak self] in
            guard !isPrepending else { return }
            self?.updateScrollPosition(old: oldConfiguration, new: configuration)
        }
    }

    private func configureCollectionView() {
        view.addSubview(collectionView)
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            collectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            collectionView.topAnchor.constraint(equalTo: view.topAnchor),
            collectionView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])

        collectionView.backgroundColor = .clear
        collectionView.alwaysBounceVertical = true
        collectionView.keyboardDismissMode = .interactive
        collectionView.delaysContentTouches = false
        collectionView.delegate = self
        collectionView.accessibilityIdentifier = "chat.timeline.collectionView"
        collectionView.accessibilityValue = nil

        if #available(iOS 26.0, *) {
            collectionView.topEdgeEffect.style = .soft
            collectionView.bottomEdgeEffect.style = .soft
        }
    }

    private func invalidateLayoutAfterBoundsChangeIfNeeded() {
        let size = collectionView.bounds.size
        guard size.width > 0, size.height > 0 else { return }
        guard abs(size.width - lastCollectionBoundsSize.width) >= 0.5
            || abs(size.height - lastCollectionBoundsSize.height) >= 0.5
        else {
            return
        }

        let hadKnownSize = lastCollectionBoundsSize != .zero
        let wasPinnedToBottom = isPinnedToBottom
        lastCollectionBoundsSize = size
        collectionView.collectionViewLayout.invalidateLayout()
        collectionView.visibleCells.forEach { $0.setNeedsLayout() }
        if hadKnownSize, wasPinnedToBottom {
            DispatchQueue.main.async { [weak self] in
                self?.scrollToBottom(animated: false)
            }
        }
    }

    private func apply(
        _ configuration: ChatTimelineConfiguration,
        animated: Bool,
        completion: (() -> Void)? = nil
    ) {
        let newItems = ChatTimelineItemBuilder.makeItems(
            messages: configuration.messages,
            isGenerating: configuration.isGenerating,
            showDetailedStats: configuration.showDetailedStats,
            extractionPhase: configuration.extractionPhase,
            backgroundDiagnostics: configuration.backgroundDiagnostics,
            hasEarlierMessages: configuration.hasEarlierMessages,
            isLoadingEarlierMessages: configuration.isLoadingEarlierMessages
        )
        items = newItems

        updatePerformanceCompletionAccessibility(newItems)
        timelineDataSource.apply(items: newItems, animated: animated) { [weak self] in
            guard let self else { return }
            if self.isApplyingPrepend {
                self.restoreOffsetAfterPrepend()
                self.isApplyingPrepend = false
            }
            completion?()
            self.startPerformanceAutoScrollIfNeeded()
        }
    }

    private func updatePerformanceCompletionAccessibility(_ items: [ChatTimelineItem]) {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains(UITestingSupport.performanceLaunchArgument),
           items.contains(.performanceCompletion) {
            collectionView.accessibilityValue = "chat.performanceGenerationComplete"
        } else {
            collectionView.accessibilityValue = nil
        }
        #endif
    }

    private func startPerformanceAutoScrollIfNeeded() {
        #if DEBUG
        guard performanceAutoScrollProbe == nil else { return }
        guard ProcessInfo.processInfo.arguments.contains(UITestingSupport.performanceAutoScrollLaunchArgument) else {
            return
        }
        guard collectionView.bounds.height > 0, collectionView.contentSize.height > collectionView.bounds.height else {
            return
        }
        let probe = ChatTimelineAutoScrollProbe(collectionView: collectionView)
        performanceAutoScrollProbe = probe
        probe.start()
        #endif
    }

    private func updateScrollPosition(old: ChatTimelineConfiguration, new: ChatTimelineConfiguration) {
        guard !isApplyingPrepend else { return }

        if old.messages.isEmpty && !new.messages.isEmpty {
            scrollToBottom(animated: false)
            return
        }

        if old.isGenerating != new.isGenerating {
            if new.isGenerating {
                shouldFollowStreaming = true
                scrollToBottom(animated: true)
            } else {
                shouldFollowStreaming = false
                cancelStreamingScroll()
                cancelFollowResume()
            }
            return
        }

        if old.messages.count < new.messages.count {
            if new.isGenerating {
                guard shouldFollowStreaming else { return }
                scrollToBottom(animated: true)
            } else if old.messages.last?.id != new.messages.last?.id {
                scrollToBottom(animated: true)
            }
            return
        }

        if old.latestStreamingRevision != new.latestStreamingRevision {
            scheduleStreamingScroll()
        }
    }

    private func isPrependingMessages(old: [MessageDisplayItem], new: [MessageDisplayItem]) -> Bool {
        guard let oldFirst = old.first, let oldLast = old.last, old.count < new.count else { return false }
        return new.contains(where: { $0.id == oldFirst.id }) && new.last?.id == oldLast.id
    }

    private func restoreOffsetAfterPrepend() {
        collectionView.layoutIfNeeded()
        let newHeight = collectionView.collectionViewLayout.collectionViewContentSize.height
        let delta = newHeight - previousContentHeight
        performProgrammaticScroll(animated: false) {
            collectionView.contentOffset.y = previousContentOffsetY + delta
        }
    }

    private func scrollToBottom(animated: Bool) {
        collectionView.layoutIfNeeded()
        guard !items.isEmpty else { return }
        let lastIndex = items.count - 1
        let indexPath = IndexPath(item: lastIndex, section: 0)
        performProgrammaticScroll(animated: animated) {
            collectionView.scrollToItem(at: indexPath, at: .bottom, animated: animated)
        }
    }

    private func triggerLoadEarlierIfNeeded() {
        guard configuration.hasEarlierMessages, !configuration.isLoadingEarlierMessages else { return }
        guard collectionView.contentOffset.y < 260 else { return }
        configuration.onLoadEarlier()
    }

    private func cancelStreamingScroll() {
        scheduledStreamingScroll?.cancel()
        scheduledStreamingScroll = nil
    }

    private func cancelFollowResume() {
        resumeFollowWorkItem?.cancel()
        resumeFollowWorkItem = nil
    }

    private func scheduleStreamingScroll() {
        guard configuration.isGenerating, shouldFollowStreaming else {
            cancelStreamingScroll()
            return
        }
        guard scheduledStreamingScroll == nil else { return }

        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.scrollToBottom(animated: false)
            self.scheduledStreamingScroll = nil
        }
        scheduledStreamingScroll = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05, execute: workItem)
    }

    private func scheduleFollowResume() {
        guard configuration.isGenerating else {
            cancelFollowResume()
            return
        }
        cancelFollowResume()
        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.shouldFollowStreaming = true
            self.scrollToBottom(animated: true)
            self.resumeFollowWorkItem = nil
        }
        resumeFollowWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: workItem)
    }

    private func setTimelineScrolling(_ isScrolling: Bool) {
        guard isReportingScrolling != isScrolling else { return }
        scrollIdleWorkItem?.cancel()
        scrollIdleWorkItem = nil
        lastScrollIdleScheduleTime = 0
        isReportingScrolling = isScrolling
        configuration.onScrollingChanged(isScrolling)
    }

    private func scheduleTimelineScrollingIdle() {
        let now = CACurrentMediaTime()
        if scrollIdleWorkItem != nil, now - lastScrollIdleScheduleTime < 0.05 {
            return
        }
        lastScrollIdleScheduleTime = now
        scrollIdleWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            self?.setTimelineScrolling(false)
        }
        scrollIdleWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18, execute: workItem)
    }

    private func performProgrammaticScroll(animated: Bool, _ action: () -> Void) {
        suppressScrollReportingUntil = CACurrentMediaTime() + (animated ? 0.45 : 0.08)
        action()
    }

    private var shouldReportObservedScroll: Bool {
        CACurrentMediaTime() >= suppressScrollReportingUntil
    }

    private var isPinnedToBottom: Bool {
        let maxOffsetY = max(
            -collectionView.adjustedContentInset.top,
            collectionView.contentSize.height - collectionView.bounds.height + collectionView.adjustedContentInset.bottom
        )
        return maxOffsetY - collectionView.contentOffset.y <= 24
    }
}

extension ChatTimelineViewController: UICollectionViewDelegateFlowLayout {
    func collectionView(
        _ collectionView: UICollectionView,
        layout collectionViewLayout: UICollectionViewLayout,
        sizeForItemAt indexPath: IndexPath
    ) -> CGSize {
        guard items.indices.contains(indexPath.item) else {
            return CGSize(width: collectionView.bounds.width, height: 1)
        }
        let width = max(collectionView.bounds.width, 1)
        let height = ChatTimelineHeightMeasurer.height(
            for: items[indexPath.item],
            containerWidth: width,
            viewportHeight: collectionView.bounds.height
        )
        return CGSize(width: width, height: height)
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        triggerLoadEarlierIfNeeded()
        guard shouldReportObservedScroll else { return }
        setTimelineScrolling(true)
        scheduleTimelineScrollingIdle()
    }

    func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        setTimelineScrolling(true)
        if configuration.isGenerating {
            shouldFollowStreaming = false
            cancelFollowResume()
        }
    }

    func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        if decelerate {
            setTimelineScrolling(true)
        } else {
            scheduleTimelineScrollingIdle()
        }
        if configuration.isGenerating, !decelerate {
            scheduleFollowResume()
        }
    }

    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        scheduleTimelineScrollingIdle()
        if configuration.isGenerating {
            scheduleFollowResume()
        }
    }
}

#if DEBUG
private final class ChatTimelineAutoScrollProbe: @unchecked Sendable {
    private weak var collectionView: UICollectionView?
    private var displayLink: CADisplayLink?
    private var startedAt: CFTimeInterval?
    private var previousTimestamp: CFTimeInterval?
    private var previousMemorySampleTimestamp: CFTimeInterval = 0
    private var intervals: [TimeInterval] = []
    private var direction: CGFloat = -1
    private let duration: TimeInterval
    private let autoExit: Bool
    private let fixtureMessageCount: Int
    private let startCPUTime: TimeInterval
    private let startRSSBytes: UInt64
    private var peakRSSBytes: UInt64

    init(collectionView: UICollectionView) {
        self.collectionView = collectionView
        duration = Self.durationArgument()
        autoExit = ProcessInfo.processInfo.arguments.contains(UITestingSupport.performanceAutoExitLaunchArgument)
        fixtureMessageCount = Self.messageCountArgument()
        startCPUTime = Self.processCPUTime()
        startRSSBytes = Self.residentMemoryBytes()
        peakRSSBytes = startRSSBytes
    }

    func start() {
        guard displayLink == nil else { return }
        let link = CADisplayLink(target: self, selector: #selector(displayLinkDidTick(_:)))
        if #available(iOS 15.0, *) {
            link.preferredFrameRateRange = CAFrameRateRange(minimum: 60, maximum: 120, preferred: 120)
        }
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    func stop() {
        displayLink?.invalidate()
        displayLink = nil
    }

    @MainActor
    @objc private func displayLinkDidTick(_ link: CADisplayLink) {
        guard let collectionView else {
            finish(link: link)
            return
        }

        if startedAt == nil {
            startedAt = link.timestamp
            previousTimestamp = link.timestamp
            previousMemorySampleTimestamp = link.timestamp
            collectionView.layoutIfNeeded()
            scrollToBottom(collectionView)
            return
        }

        guard let startedAt, let previousTimestamp else { return }
        let elapsed = link.timestamp - startedAt
        let frameInterval = link.timestamp - previousTimestamp
        intervals.append(frameInterval)
        self.previousTimestamp = link.timestamp

        if link.timestamp - previousMemorySampleTimestamp > 0.25 {
            peakRSSBytes = max(peakRSSBytes, Self.residentMemoryBytes())
            previousMemorySampleTimestamp = link.timestamp
        }

        if elapsed >= duration {
            finish(link: link)
            return
        }

        scroll(collectionView, deltaTime: frameInterval)
    }

    @MainActor
    private func scroll(_ collectionView: UICollectionView, deltaTime: TimeInterval) {
        collectionView.layoutIfNeeded()
        let minY = -collectionView.adjustedContentInset.top
        let maxY = max(
            minY,
            collectionView.contentSize.height - collectionView.bounds.height + collectionView.adjustedContentInset.bottom
        )
        guard maxY - minY > 32 else { return }

        if collectionView.contentOffset.y <= minY + 24 {
            direction = 1
        } else if collectionView.contentOffset.y >= maxY - 24 {
            direction = -1
        }

        let velocity = max(collectionView.bounds.height * 1.45, 760)
        let nextY = collectionView.contentOffset.y + direction * velocity * CGFloat(deltaTime)
        collectionView.setContentOffset(
            CGPoint(x: collectionView.contentOffset.x, y: min(max(nextY, minY), maxY)),
            animated: false
        )
    }

    @MainActor
    private func scrollToBottom(_ collectionView: UICollectionView) {
        let minY = -collectionView.adjustedContentInset.top
        let maxY = max(
            minY,
            collectionView.contentSize.height - collectionView.bounds.height + collectionView.adjustedContentInset.bottom
        )
        collectionView.setContentOffset(CGPoint(x: collectionView.contentOffset.x, y: maxY), animated: false)
    }

    @MainActor
    private func finish(link: CADisplayLink) {
        stop()
        peakRSSBytes = max(peakRSSBytes, Self.residentMemoryBytes())
        let endRSSBytes = Self.residentMemoryBytes()
        let cpuTime = Self.processCPUTime() - startCPUTime
        let sortedIntervals = intervals.sorted()
        let average = intervals.isEmpty ? 0 : intervals.reduce(0, +) / Double(intervals.count)
        let p95 = percentile(0.95, sortedIntervals: sortedIntervals)
        let maximum = sortedIntervals.last ?? 0
        let over16 = intervals.filter { $0 > 0.0167 }.count
        let over33 = intervals.filter { $0 > 0.0334 }.count
        let loadedItems = collectionView?.numberOfItems(inSection: 0) ?? 0

        print(
            String(
                format: "OPENCHAT_PERF_AUTOSCROLL_RESULT fixture_messages=%d duration_s=%.3f frames=%d avg_frame_ms=%.3f p95_frame_ms=%.3f max_frame_ms=%.3f frames_over_16_7_ms=%d frames_over_33_4_ms=%d cpu_time_s=%.3f rss_start_kb=%llu rss_end_kb=%llu rss_peak_kb=%llu loaded_timeline_items=%d",
                fixtureMessageCount,
                duration,
                intervals.count,
                average * 1_000,
                p95 * 1_000,
                maximum * 1_000,
                over16,
                over33,
                cpuTime,
                startRSSBytes / 1_024,
                endRSSBytes / 1_024,
                peakRSSBytes / 1_024,
                loadedItems
            )
        )
        fflush(stdout)

        if autoExit {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                exit(0)
            }
        }
    }

    private func percentile(_ percentile: Double, sortedIntervals: [TimeInterval]) -> TimeInterval {
        guard !sortedIntervals.isEmpty else { return 0 }
        let index = min(sortedIntervals.count - 1, max(0, Int(Double(sortedIntervals.count - 1) * percentile)))
        return sortedIntervals[index]
    }

    private static func durationArgument() -> TimeInterval {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "--ui-testing-chat-performance-autoscroll-duration"),
              arguments.indices.contains(index + 1),
              let value = Double(arguments[index + 1])
        else {
            return 8
        }
        return min(max(value, 2), 30)
    }

    private static func messageCountArgument() -> Int {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "--ui-testing-chat-performance-count"),
              arguments.indices.contains(index + 1),
              let count = Int(arguments[index + 1])
        else {
            return 1_000
        }
        return min(max(count, 1), 10_000)
    }

    private static func processCPUTime() -> TimeInterval {
        var usage = rusage()
        guard getrusage(RUSAGE_SELF, &usage) == 0 else { return 0 }
        return timevalSeconds(usage.ru_utime) + timevalSeconds(usage.ru_stime)
    }

    private static func timevalSeconds(_ value: timeval) -> TimeInterval {
        TimeInterval(value.tv_sec) + TimeInterval(value.tv_usec) / 1_000_000
    }

    private static func residentMemoryBytes() -> UInt64 {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size / MemoryLayout<natural_t>.size)
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { reboundPointer in
                task_info(
                    mach_task_self_,
                    task_flavor_t(MACH_TASK_BASIC_INFO),
                    reboundPointer,
                    &count
                )
            }
        }
        guard result == KERN_SUCCESS else { return 0 }
        return UInt64(info.resident_size)
    }
}
#endif
