import SwiftUI

/// phase-07 §9 — one screen that changes shape as generation progresses,
/// same discipline as `VideoUploadFlowView`'s upload stages.
enum LessonCreationStage: Equatable {
    case idle
    case generating
    case ready(videoId: String)
    case failed(message: String, canRetry: Bool)
    /// The learner's own wallet can't cover this lesson — distinct from
    /// `.failed` so the UI can offer a "Top up" button instead of "Retry"
    /// (retrying an unaffordable lesson just fails again the same way).
    case insufficientCredit(message: String)
    /// Shui's own Golpo/Anthropic account is out of tracked credit — a
    /// platform-wide outage, not something retrying or topping up the
    /// learner's own wallet fixes.
    case platformOffline(message: String)

    var isBusy: Bool {
        self == .generating
    }
}

/// The two stages generation genuinely goes through — not a fake progress
/// bar. `createOnDemandLesson` doesn't return until the script and quiz are
/// written; only after that does the render start being polled.
enum LessonGenerationPhase: Equatable {
    case writingScript
    case animating

    var title: String {
        switch self {
        case .writingScript: return "Writing your script"
        case .animating: return "Animating your lesson"
        }
    }

    var detail: String {
        switch self {
        case .writingScript: return "Researching your topic and drafting a quiz."
        case .animating: return "Drawing scenes and adding narration."
        }
    }
}

@MainActor
final class CreateLessonViewModel: ObservableObject {
    /// Matches `CreateOnDemandLessonInputSchema`'s `topic` max.
    static let topicLimit = 300

    @Published var topic: String
    @Published private(set) var duration: LessonDuration = .thirtySeconds
    @Published var format: LessonFormat = .vertical
    @Published private(set) var stage: LessonCreationStage = .idle
    @Published private(set) var phase: LessonGenerationPhase = .writingScript
    @Published private(set) var wallet: Wallet?

    private let environment: AppEnvironment
    private var pollTask: Task<Void, Never>?
    /// Once the learner taps a length, a wallet reload (returning from
    /// Billing, or after generating) never overrides their pick.
    private var hasChosenDuration = false
    /// A locked length tapped on the way to upgrading — selected
    /// automatically if the reload afterwards shows it's now unlocked.
    private var durationAwaitingUpgrade: LessonDuration?

    init(environment: AppEnvironment, initialTopic: String = "") {
        self.environment = environment
        self.topic = initialTopic
    }

    var trimmedTopic: String { topic.trimmingCharacters(in: .whitespacesAndNewlines) }
    var canSubmit: Bool { !trimmedTopic.isEmpty && !stage.isBusy }
    var tierInfo: TierInfo { TierInfo.info(for: wallet?.tier ?? .free) }

    private var isFirstFreeLesson: Bool {
        guard let wallet else { return false }
        return wallet.tier == .free && !wallet.hasUsedFreeLesson
    }

    func isLocked(_ duration: LessonDuration) -> Bool {
        !tierInfo.allows(duration)
    }

    func priceLabel(for duration: LessonDuration) -> String {
        if isFirstFreeLesson && tierInfo.allows(duration) { return "Free" }
        return Self.currency(tierInfo.costCents(for: duration))
    }

    /// `nil` until the wallet loads. The server is the real price check, so
    /// an unloaded wallet never blocks generating.
    var selectedCostCents: Int? {
        guard wallet != nil else { return nil }
        return isFirstFreeLesson ? 0 : tierInfo.costCents(for: duration)
    }

    var canAfford: Bool {
        guard let wallet, let cost = selectedCostCents else { return true }
        return wallet.creditBalanceCents >= cost
    }

    var balanceCaption: String? {
        guard let wallet, let cost = selectedCostCents else { return nil }
        if cost == 0 { return "Your first lesson is free" }
        if !canAfford { return "\(Self.currency(cost - wallet.creditBalanceCents)) short" }
        return "\(Self.currency(wallet.creditBalanceCents - cost)) after this lesson"
    }

    var generateTitle: String {
        guard let cost = selectedCostCents else { return "Generate" }
        if !canAfford { return wallet?.tier == .free ? "Upgrade to generate" : "Top up to generate" }
        return cost == 0 ? "Generate · Free" : "Generate · \(Self.currency(cost))"
    }

    func select(_ duration: LessonDuration) {
        hasChosenDuration = true
        self.duration = duration
    }

    func noteLockedTap(_ duration: LessonDuration) {
        durationAwaitingUpgrade = duration
    }

    func loadWallet() async {
        wallet = try? await environment.billing.wallet()
        if let pending = durationAwaitingUpgrade, tierInfo.allows(pending) {
            select(pending)
        } else if !hasChosenDuration || isLocked(duration) {
            // The longest length the tier allows — what every lesson got
            // before lengths were selectable.
            duration = LessonDuration.allCases.last(where: tierInfo.allows) ?? .thirtySeconds
        }
        durationAwaitingUpgrade = nil
    }

    func generate() {
        let topic = trimmedTopic
        guard !topic.isEmpty, !stage.isBusy else { return }
        AppAnalytics.logFeatureTap(.createLesson)
        let chosenDuration = duration
        let chosenOrientation = format.orientation
        phase = .writingScript
        stage = .generating
        Task {
            do {
                let (videoId, status) = try await environment.onDemandLessons.createLesson(
                    topic: topic, duration: chosenDuration, orientation: chosenOrientation
                )
                if status == "ready" {
                    stage = .ready(videoId: videoId)
                } else {
                    phase = .animating
                    startPolling(videoId: videoId)
                }
            } catch let error as OnDemandLessonError {
                switch error {
                case .insufficientCredit(let message):
                    stage = .insufficientCredit(message: message)
                case .platformUnavailable(let message):
                    stage = .platformOffline(message: message)
                default:
                    stage = .failed(message: error.localizedDescription, canRetry: true)
                }
            } catch {
                stage = .failed(message: error.localizedDescription, canRetry: true)
            }
            await loadWallet()
        }
    }

    private func startPolling(videoId: String) {
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            guard let self else { return }
            // GolpoAI reports no granular progress (phase-07 §9) — this
            // loop's only job is to notice a terminal state, not to show one
            // faster than it actually arrives.
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                guard !Task.isCancelled else { return }
                do {
                    let (status, message) = try await self.environment.onDemandLessons.checkStatus(videoId: videoId)
                    switch status {
                    case "ready":
                        self.stage = .ready(videoId: videoId)
                        return
                    case "failed":
                        self.stage = .failed(message: message ?? "Something went wrong generating this lesson.", canRetry: true)
                        return
                    default:
                        continue
                    }
                } catch {
                    self.stage = .failed(message: error.localizedDescription, canRetry: true)
                    return
                }
            }
        }
    }

    func retry() {
        stage = .idle
        generate()
    }

    func cancelPolling() {
        pollTask?.cancel()
    }

    private static func currency(_ cents: Int) -> String {
        (Double(cents) / 100).formatted(.currency(code: "USD"))
    }
}

/// A composer, not a form: the topic gets the whole stage, length and
/// format sit right under it as tappable cards (each length showing its
/// own price), and everything about money — tier, balance, what's left
/// after — lives in one bar welded to the Generate button, which itself
/// carries the exact price. Platform formats stay folded away until asked
/// for, since most people only ever want Vertical.
struct CreateLessonView: View {
    let environment: AppEnvironment
    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @StateObject private var viewModel: CreateLessonViewModel
    @State private var readyVideo: Video?
    @State private var showBilling = false
    @State private var showPlatformFormats = false
    @State private var burstTrigger = 0
    @State private var selectionTick = 0
    @State private var isLaunching = false
    @FocusState private var topicFieldFocused: Bool

    init(environment: AppEnvironment, initialTopic: String = "") {
        self.environment = environment
        _viewModel = StateObject(wrappedValue: CreateLessonViewModel(environment: environment, initialTopic: initialTopic))
    }

    var body: some View {
        NavigationStack {
            ZStack {
                switch viewModel.stage {
                case .idle:
                    composer
                        .transition(.opacity.combined(with: .scale(scale: 0.98)))
                case .generating:
                    generatingView
                        .transition(.opacity.combined(with: .scale(scale: 1.03)))
                case .ready(let videoId):
                    readyView(videoId: videoId)
                        .transition(.opacity)
                case .failed(let message, let canRetry):
                    failedView(message: message, canRetry: canRetry)
                        .transition(.opacity)
                case .insufficientCredit(let message):
                    insufficientCreditView(message: message)
                        .transition(.opacity)
                case .platformOffline(let message):
                    platformOfflineView(message: message)
                        .transition(.opacity)
                }
            }
            .animation(reduceMotion ? nil : Animation.smooth(duration: 0.5), value: viewModel.stage)
            .navigationTitle("New lesson")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                // "Close", not "Cancel", once generation has started —
                // the render (and its credit charge) keeps going in the
                // background regardless, exactly as this screen's own
                // copy says; a "Cancel" label here would wrongly imply
                // tapping it stops the charge.
                ToolbarItem(placement: .cancellationAction) {
                    Button(viewModel.stage.isBusy ? Strings.close : Strings.cancel) {
                        viewModel.cancelPolling()
                        dismiss()
                    }
                }
            }
            // Not disabled while generating — the screen's own copy
            // already tells the learner it's safe to leave (the render
            // continues server-side), so swipe-to-dismiss should behave
            // the same as the toolbar's "Close" button, not fight it.
            .task { await viewModel.loadWallet() }
            .shuiShellBackground()
        }
        .sensoryFeedback(.selection, trigger: selectionTick)
        .sensoryFeedback(.impact(flexibility: .soft, intensity: 0.9), trigger: burstTrigger)
        .sensoryFeedback(.success, trigger: viewModel.stage) { _, newValue in
            if case .ready = newValue { return true }
            return false
        }
        .fullScreenCover(item: $readyVideo) { video in
            FeedView(mode: .videoList(videos: [video]), environment: environment)
        }
        .sheet(isPresented: $showBilling, onDismiss: { Task { await viewModel.loadWallet() } }) {
            NavigationStack {
                BillingView(environment: environment)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button(Strings.done) { showBilling = false }
                        }
                    }
            }
        }
    }

    // MARK: - Composer

    private var composer: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                header
                topicCard
                lengthSection
                formatSection
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .scrollDismissesKeyboard(.interactively)
        .safeAreaInset(edge: .bottom, spacing: 0) { summaryBar }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("What do you want to learn?")
                .font(.system(.title, design: .rounded, weight: .bold))
                .foregroundStyle(theme.textPrimary)
            Text("Shui writes the script, animates it, and adds a quiz.")
                .font(.subheadline)
                .foregroundStyle(theme.textSecondary)
        }
    }

    private var topicCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextField("e.g. How does compound interest work?", text: $viewModel.topic, axis: .vertical)
                .font(.title3)
                .foregroundStyle(theme.textPrimary)
                .lineLimit(3...6)
                .focused($topicFieldFocused)
                .submitLabel(.done)
            HStack {
                if !viewModel.topic.isEmpty {
                    Button {
                        viewModel.topic = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(theme.textSecondary)
                    .accessibilityLabel("Clear topic")
                }
                Spacer()
                Text("\(viewModel.topic.count)/\(CreateLessonViewModel.topicLimit)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(theme.textSecondary)
            }
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: Theme.cornerRadiusCard, style: .continuous)
                .fill(theme.surface)
                .shadow(color: .black.opacity(0.06), radius: 14, y: 6)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cornerRadiusCard, style: .continuous)
                .strokeBorder(
                    topicFieldFocused ? AnyShapeStyle(theme.accentGradient) : AnyShapeStyle(theme.borderSubtle),
                    lineWidth: topicFieldFocused ? 2 : 1
                )
        )
        .contentShape(Rectangle())
        .onTapGesture { topicFieldFocused = true }
        .animation(.snappy, value: topicFieldFocused)
        // A multi-line field's return key inserts a newline; here it means
        // "done" instead, and the topic never carries line breaks or runs
        // past the server's limit.
        .onChange(of: viewModel.topic) { _, newValue in
            var cleaned = newValue
            if cleaned.contains("\n") {
                cleaned = cleaned.replacingOccurrences(of: "\n", with: " ")
                topicFieldFocused = false
            }
            if cleaned.count > CreateLessonViewModel.topicLimit {
                cleaned = String(cleaned.prefix(CreateLessonViewModel.topicLimit))
            }
            if cleaned != newValue {
                viewModel.topic = cleaned
            }
        }
    }

    private var lengthSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionLabel("Length", systemImage: "timer")
            HStack(spacing: 8) {
                ForEach(LessonDuration.allCases) { duration in
                    durationChip(duration)
                }
            }
        }
    }

    private func durationChip(_ duration: LessonDuration) -> some View {
        let locked = viewModel.isLocked(duration)
        let selected = !locked && viewModel.duration == duration
        let requiredTier = TierInfo.minimumTier(for: duration)?.displayName ?? "an upgrade"
        return Button {
            selectionTick += 1
            if locked {
                viewModel.noteLockedTap(duration)
                showBilling = true
            } else {
                withAnimation(.snappy) { viewModel.select(duration) }
            }
        } label: {
            VStack(spacing: 3) {
                Text(duration.label)
                    .font(.subheadline.weight(.semibold))
                if locked {
                    Label(requiredTier, systemImage: "lock.fill")
                        .font(.caption2)
                } else {
                    Text(viewModel.priceLabel(for: duration))
                        .font(.caption2.monospacedDigit())
                }
            }
            .lineLimit(1)
            .minimumScaleFactor(0.75)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .foregroundStyle(selected ? theme.textOnAccent : (locked ? theme.textSecondary : theme.textPrimary))
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(selected ? AnyShapeStyle(theme.accentGradient) : AnyShapeStyle(locked ? theme.surfaceSubtle : theme.surface))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(selected ? Color.clear : theme.borderSubtle, lineWidth: 1)
            )
            .scaleEffect(selected ? 1.03 : 1)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(locked ? "\(duration.spokenLabel), requires \(requiredTier)" : "\(duration.spokenLabel), \(viewModel.priceLabel(for: duration))")
        .accessibilityHint(locked ? "Opens plans" : "")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var formatSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionLabel("Format", systemImage: "aspectratio")
            HStack(spacing: 10) {
                ForEach(LessonFormat.basics) { format in
                    formatCard(format, stacked: false)
                }
            }
            Button {
                withAnimation(.snappy) { showPlatformFormats.toggle() }
            } label: {
                HStack(spacing: 6) {
                    Text(viewModel.format.isPlatformPreset ? "Made for \(viewModel.format.title)" : "Formats for TikTok, Reels, YouTube")
                    Image(systemName: "chevron.down")
                        .rotationEffect(.degrees(showPlatformFormats ? 180 : 0))
                }
                .font(.subheadline.weight(.medium))
                .foregroundStyle(theme.accent)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(showPlatformFormats ? "Hide platform formats" : "Show platform formats")

            if showPlatformFormats {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                    ForEach(LessonFormat.platforms) { format in
                        formatCard(format, stacked: true)
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
                Text("These use the same two sizes as Vertical and Horizontal — the name just helps you pick.")
                    .font(.caption)
                    .foregroundStyle(theme.textSecondary)
                    .transition(.opacity)
            }
        }
    }

    private func formatCard(_ format: LessonFormat, stacked: Bool) -> some View {
        let selected = viewModel.format == format
        return Button {
            selectionTick += 1
            withAnimation(.snappy) { viewModel.format = format }
        } label: {
            Group {
                if stacked {
                    VStack(alignment: .leading, spacing: 8) {
                        AspectGlyph(aspectRatio: format.orientation.aspectRatio)
                            .foregroundStyle(selected ? theme.accent : theme.textSecondary)
                        formatText(format)
                    }
                } else {
                    HStack(spacing: 12) {
                        AspectGlyph(aspectRatio: format.orientation.aspectRatio)
                            .foregroundStyle(selected ? theme.accent : theme.textSecondary)
                        formatText(format)
                    }
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(theme.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(
                        selected ? AnyShapeStyle(theme.accentGradient) : AnyShapeStyle(theme.borderSubtle),
                        lineWidth: selected ? 2 : 1
                    )
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(format.title), \(format.detail)")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func formatText(_ format: LessonFormat) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(format.title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(theme.textPrimary)
            Text(format.detail)
                .font(.caption.monospacedDigit())
                .foregroundStyle(theme.textSecondary)
        }
        .lineLimit(1)
        .minimumScaleFactor(0.8)
    }

    private func sectionLabel(_ title: String, systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
            .font(.footnote.weight(.semibold))
            .textCase(.uppercase)
            .tracking(0.6)
            .foregroundStyle(theme.textSecondary)
    }

    // MARK: - Summary bar

    private var summaryBar: some View {
        VStack(spacing: 12) {
            walletRow
            Button(action: launch) {
                Label(viewModel.generateTitle, systemImage: "sparkles")
                    .contentTransition(.numericText())
            }
            .buttonStyle(.shuiPill)
            .disabled(!viewModel.canSubmit || isLaunching)
            .overlay { GenerateBurst(trigger: burstTrigger, colors: theme.accentGradientStops) }
            .animation(.snappy, value: viewModel.generateTitle)
        }
        .padding(.horizontal, 20)
        .padding(.top, 14)
        .padding(.bottom, 10)
        .background(.bar)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(theme.borderSubtle)
                .frame(height: 0.5)
        }
    }

    private var walletRow: some View {
        Button {
            showBilling = true
        } label: {
            HStack(spacing: 10) {
                Label(viewModel.tierInfo.displayName, systemImage: "diamond.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(theme.accent)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(theme.surfaceSubtle))
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 1) {
                    HStack(spacing: 4) {
                        Text("Balance")
                            .foregroundStyle(theme.textSecondary)
                        Text(viewModel.wallet?.creditBalanceDisplay ?? "$0.00")
                            .fontWeight(.semibold)
                            .foregroundStyle(theme.textPrimary)
                            .monospacedDigit()
                    }
                    .font(.subheadline)
                    if let caption = viewModel.balanceCaption {
                        Text(caption)
                            .font(.caption2)
                            .foregroundStyle(viewModel.canAfford ? theme.textSecondary : theme.warning)
                    }
                }
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(theme.textSecondary)
            }
            .redacted(reason: viewModel.wallet == nil ? .placeholder : [])
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(viewModel.wallet == nil)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens plans and balance")
    }

    private func launch() {
        guard viewModel.canSubmit, !isLaunching else { return }
        guard viewModel.canAfford else {
            showBilling = true
            return
        }
        topicFieldFocused = false
        isLaunching = true
        burstTrigger += 1
        SoundEffect.generate.play()
        Task { @MainActor in
            // Lets the burst play out over the button before the stage
            // change swaps the whole composer out from under it.
            if !reduceMotion {
                try? await Task.sleep(for: .milliseconds(480))
            }
            viewModel.generate()
            isLaunching = false
        }
    }

    // MARK: - Generating

    private var generatingView: some View {
        VStack(spacing: 28) {
            Spacer()
            LessonOrb(colors: theme.accentGradientStops)
            VStack(spacing: 10) {
                ZStack {
                    Text(viewModel.phase.title)
                        .font(.system(.title2, design: .rounded, weight: .bold))
                        .foregroundStyle(theme.textPrimary)
                        .id(viewModel.phase)
                        .transition(.opacity.combined(with: .offset(y: 8)))
                }
                Text(viewModel.phase.detail)
                    .font(.subheadline)
                    .foregroundStyle(theme.textSecondary)
                    .id(viewModel.phase)
                    .transition(.opacity)
                phaseSteps
                    .padding(.top, 6)
            }
            .animation(.smooth(duration: 0.45), value: viewModel.phase)
            .multilineTextAlignment(.center)

            Text("“\(viewModel.trimmedTopic)”")
                .font(.subheadline.italic())
                .foregroundStyle(theme.textSecondary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
            Spacer()
            Text("Usually a minute or two. You can leave — it keeps going in the background.")
                .font(.footnote)
                .foregroundStyle(theme.textSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 32)
        .padding(.bottom, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var phaseSteps: some View {
        HStack(spacing: 10) {
            stepLabel("Script", done: viewModel.phase == .animating, active: viewModel.phase == .writingScript)
            Capsule()
                .fill(theme.borderSubtle)
                .frame(width: 20, height: 2)
            stepLabel("Animation", done: false, active: viewModel.phase == .animating)
        }
        .accessibilityElement(children: .combine)
    }

    private func stepLabel(_ title: String, done: Bool, active: Bool) -> some View {
        Label(title, systemImage: done ? "checkmark.circle.fill" : (active ? "circle.dotted" : "circle"))
            .font(.caption.weight(.semibold))
            .foregroundStyle(done ? theme.success : (active ? theme.accent : theme.textSecondary))
            .symbolEffect(.pulse, isActive: active && !reduceMotion)
    }

    // MARK: - Terminal states

    private func readyView(videoId: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 52))
                .foregroundStyle(theme.success)
                .symbolEffect(.bounce, value: videoId)
            Text("Your lesson is ready")
                .font(.system(.title3, design: .rounded, weight: .bold))
                .foregroundStyle(theme.textPrimary)
            Button("Watch it") {
                Task {
                    readyVideo = try? await environment.videos.video(id: videoId)
                }
            }
            .buttonStyle(.shuiPill)
            .padding(.horizontal, 24)
            Button(Strings.done) { dismiss() }
                .buttonStyle(.shuiPillOutline)
                .padding(.horizontal, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func failedView(message: String, canRetry: Bool) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 36))
                .foregroundStyle(theme.error)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(theme.textPrimary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            if canRetry {
                Button(Strings.retry) { viewModel.retry() }
                    .buttonStyle(.shuiPill)
                    .padding(.horizontal, 24)
            }
            Button(Strings.cancel, role: .cancel) { dismiss() }
                .buttonStyle(.shuiPillOutline)
                .padding(.horizontal, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func insufficientCreditView(message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "creditcard.trianglebadge.exclamationmark")
                .font(.system(size: 36))
                .foregroundStyle(theme.warning)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(theme.textPrimary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Button("Top up") { showBilling = true }
                .buttonStyle(.shuiPill)
                .padding(.horizontal, 24)
            Button(Strings.cancel, role: .cancel) { dismiss() }
                .buttonStyle(.shuiPillOutline)
                .padding(.horizontal, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func platformOfflineView(message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "wrench.and.screwdriver.fill")
                .font(.system(size: 36))
                .foregroundStyle(theme.textSecondary)
            Text("We're offline for a moment")
                .font(.headline)
                .foregroundStyle(theme.textPrimary)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(theme.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Button(Strings.retry) { viewModel.retry() }
                .buttonStyle(.shuiPillOutline)
                .padding(.horizontal, 24)
            Button(Strings.cancel, role: .cancel) { dismiss() }
                .buttonStyle(.shuiPillOutline)
                .padding(.horizontal, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// A rounded outline in the format's real proportions — the shape itself
/// says "portrait" or "landscape" before the label is read.
private struct AspectGlyph: View {
    let aspectRatio: CGFloat

    var body: some View {
        RoundedRectangle(cornerRadius: 4, style: .continuous)
            .strokeBorder(lineWidth: 2)
            .aspectRatio(aspectRatio, contentMode: .fit)
            .frame(width: 26, height: 26)
            .accessibilityHidden(true)
    }
}
