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

    func title(for mode: LessonMode) -> String {
        switch (self, mode) {
        case (.writingScript, .describe): return "Writing your script"
        case (.writingScript, .script): return "Reading your script"
        case (.animating, _): return "Animating your lesson"
        }
    }

    func detail(for mode: LessonMode) -> String {
        switch (self, mode) {
        case (.writingScript, .describe): return "Researching your topic and drafting a quiz."
        case (.writingScript, .script): return "Choosing visuals and drafting a quiz."
        case (.animating, _): return "Drawing scenes and adding narration."
        }
    }
}

@MainActor
final class CreateLessonViewModel: ObservableObject {
    /// Matches `MAX_BRIEF_CHARS` server-side. A script's real limit is far
    /// lower and depends on the length (`scriptCharacterBudget`); this only
    /// caps what can be pasted while editing one down.
    static let textLimit = 5000

    @Published var mode: LessonMode
    /// Describe mode's box, and My script's — kept separate so switching
    /// modes never throws away what was typed in the other.
    @Published var topic: String {
        didSet { if topic.utf16.count > Self.textLimit { topic = Self.capped(topic) } }
    }
    @Published var script: String {
        didSet { if script.utf16.count > Self.textLimit { script = Self.capped(script) } }
    }
    @Published var purpose: LessonPurpose = .personal
    @Published var voice: LessonVoice = .auto
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

    init(environment: AppEnvironment, initialText: String = "", initialMode: LessonMode = .describe) {
        self.environment = environment
        self.mode = initialMode
        self.topic = initialMode == .describe ? initialText : ""
        self.script = initialMode == .script ? initialText : ""
    }

    /// What will actually be sent — whichever box the current mode uses.
    var activeText: String {
        (mode == .describe ? topic : script).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// In UTF-16 units, the way the server measures it.
    var activeLength: Int { activeText.utf16.count }

    var scriptOverBudget: Bool {
        mode == .script && activeLength > duration.scriptCharacterBudget
    }

    /// A brief longer than the chosen length can narrate gets condensed to
    /// its key points rather than rushed through.
    var briefWillBeCondensed: Bool {
        mode == .describe && activeLength > duration.scriptCharacterBudget
    }

    var canSubmit: Bool { !activeText.isEmpty && !stage.isBusy && !scriptOverBudget }
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
        let text = activeText
        guard !text.isEmpty, !stage.isBusy, !scriptOverBudget else { return }
        AppAnalytics.logFeatureTap(.createLesson)
        let request = LessonRequest(
            mode: mode, text: text, duration: duration, orientation: format.orientation, purpose: purpose, voice: voice
        )
        phase = .writingScript
        stage = .generating
        Task {
            do {
                let (videoId, status) = try await environment.onDemandLessons.createLesson(request)
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

    /// Trims to `textLimit` UTF-16 units without splitting a character.
    private static func capped(_ text: String) -> String {
        var result = ""
        var used = 0
        for character in text {
            let size = character.utf16.count
            if used + size > textLimit { break }
            result.append(character)
            used += size
        }
        return result
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
    @State private var showStyleOptions = false
    @FocusState private var topicFieldFocused: Bool
    @Namespace private var modeNamespace

    init(environment: AppEnvironment, initialText: String = "", initialMode: LessonMode = .describe) {
        self.environment = environment
        _viewModel = StateObject(wrappedValue: CreateLessonViewModel(
            environment: environment, initialText: initialText, initialMode: initialMode
        ))
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
                VStack(alignment: .leading, spacing: 18) {
                    header
                    modePicker
                    topicCard
                }
                lengthSection
                formatSection
                styleSection
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .scrollDismissesKeyboard(.interactively)
        .safeAreaInset(edge: .bottom, spacing: 0) { summaryBar }
        // Briefs and scripts are multi-paragraph, so Return inserts a line
        // break; this is the way out of the keyboard.
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button(Strings.done) { topicFieldFocused = false }
            }
        }
        // Voice matters most to someone writing their own narration.
        .onChange(of: viewModel.mode) { _, newValue in
            if newValue == .script {
                withAnimation(.snappy) { showStyleOptions = true }
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(viewModel.mode == .describe ? "What do you want to learn?" : "Your words, brought to life")
                .font(.system(.title, design: .rounded, weight: .bold))
                .foregroundStyle(theme.textPrimary)
            Text(viewModel.mode == .describe
                 ? "Type an idea, or paste a detailed brief — rules, steps, notes. Shui writes the script, animates it, and adds a quiz."
                 : "Shui reads your script exactly as written, animates it, and adds a quiz.")
                .font(.subheadline)
                .foregroundStyle(theme.textSecondary)
        }
        .animation(.snappy, value: viewModel.mode)
    }

    private var modePicker: some View {
        HStack(spacing: 4) {
            ForEach(LessonMode.allCases) { mode in
                let selected = viewModel.mode == mode
                Button {
                    selectionTick += 1
                    withAnimation(.snappy) { viewModel.mode = mode }
                } label: {
                    Label(mode.title, systemImage: mode.systemImage)
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .foregroundStyle(selected ? theme.textOnAccent : theme.textSecondary)
                        .background {
                            if selected {
                                Capsule()
                                    .fill(theme.accentGradient)
                                    .matchedGeometryEffect(id: "modeHighlight", in: modeNamespace)
                            }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .padding(4)
        .background(Capsule().fill(theme.surfaceSubtle))
    }

    private var activeTextBinding: Binding<String> {
        viewModel.mode == .describe ? $viewModel.topic : $viewModel.script
    }

    private var topicCard: some View {
        let overBudget = viewModel.scriptOverBudget
        return VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 12) {
                TextField(
                    viewModel.mode == .describe
                        ? "An idea — or paste your notes, rules, or steps"
                        : "Write exactly what the narrator should say…",
                    text: activeTextBinding,
                    axis: .vertical
                )
                .font(viewModel.mode == .describe ? Font.title3 : Font.body)
                .foregroundStyle(theme.textPrimary)
                .lineLimit(viewModel.mode == .describe ? 3...10 : 6...14)
                .focused($topicFieldFocused)
                // One field per mode: its binding changes with the mode, and a
                // focused field can otherwise keep showing the other mode's text.
                .id(viewModel.mode)
                HStack {
                    if !activeTextBinding.wrappedValue.isEmpty {
                        Button {
                            activeTextBinding.wrappedValue = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(theme.textSecondary)
                        .accessibilityLabel("Clear")
                    }
                    Spacer()
                    Text(counterText)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(overBudget ? theme.warning : theme.textSecondary)
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
                        overBudget
                            ? AnyShapeStyle(theme.warning)
                            : (topicFieldFocused ? AnyShapeStyle(theme.accentGradient) : AnyShapeStyle(theme.borderSubtle)),
                        lineWidth: overBudget || topicFieldFocused ? 2 : 1
                    )
            )
            .contentShape(Rectangle())
            .onTapGesture { topicFieldFocused = true }
            .animation(.snappy, value: topicFieldFocused)

            textGuidance
        }
    }

    private var counterText: String {
        let limit = viewModel.mode == .script ? viewModel.duration.scriptCharacterBudget : CreateLessonViewModel.textLimit
        return "\(viewModel.activeLength.formatted()) / \(limit.formatted())"
    }

    /// What the text in the box will turn into at the chosen length.
    @ViewBuilder
    private var textGuidance: some View {
        let duration = viewModel.duration
        switch viewModel.mode {
        case .describe:
            if viewModel.briefWillBeCondensed {
                guidanceLabel(
                    "More than a \(duration.adjective) lesson can cover — Shui will focus on the key points.",
                    systemImage: "text.badge.checkmark",
                    color: theme.textSecondary
                )
            }
        case .script:
            if viewModel.scriptOverBudget {
                guidanceLabel(
                    "Too long for a \(duration.adjective) lesson — shorten it or pick a longer length.",
                    systemImage: "exclamationmark.triangle.fill",
                    color: theme.warning
                )
            } else {
                guidanceLabel(
                    "Read exactly as written. A \(duration.adjective) lesson fits up to \(duration.scriptCharacterBudget.formatted()) characters, about \((duration.scriptCharacterBudget / 6).formatted()) words.",
                    systemImage: "info.circle",
                    color: theme.textSecondary
                )
            }
        }
    }

    private func guidanceLabel(_ text: String, systemImage: String, color: Color) -> some View {
        Label(text, systemImage: systemImage)
            .font(.footnote)
            .foregroundStyle(color)
            .padding(.horizontal, 4)
            .transition(.opacity)
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

    private var styleSection: some View {
        let twoColumns = [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)]
        return VStack(alignment: .leading, spacing: 12) {
            Button {
                withAnimation(.snappy) { showStyleOptions.toggle() }
            } label: {
                HStack(spacing: 8) {
                    sectionLabel("Voice & purpose", systemImage: "waveform")
                    Spacer(minLength: 8)
                    if !showStyleOptions {
                        Text("\(viewModel.purpose.title) · \(viewModel.voice == .auto ? "Auto voice" : "\(viewModel.voice.title) voice")")
                            .font(.footnote)
                            .foregroundStyle(theme.textSecondary)
                            .lineLimit(1)
                    }
                    Image(systemName: "chevron.down")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(theme.textSecondary)
                        .rotationEffect(.degrees(showStyleOptions ? 180 : 0))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(showStyleOptions ? "Hide voice and purpose" : "Voice and purpose: \(viewModel.purpose.title), \(viewModel.voice.title) voice")

            if showStyleOptions {
                VStack(alignment: .leading, spacing: 10) {
                    optionGroupLabel("Made for")
                    LazyVGrid(columns: twoColumns, spacing: 10) {
                        ForEach(LessonPurpose.allCases) { purpose in
                            optionCard(title: purpose.title, detail: purpose.detail, systemImage: purpose.systemImage,
                                       selected: viewModel.purpose == purpose) { viewModel.purpose = purpose }
                        }
                    }
                    optionGroupLabel("Voice")
                        .padding(.top, 6)
                    LazyVGrid(columns: twoColumns, spacing: 10) {
                        ForEach(LessonVoice.allCases) { voice in
                            optionCard(title: voice.title, detail: voice.detail, systemImage: voice.systemImage,
                                       selected: viewModel.voice == voice) { viewModel.voice = voice }
                        }
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    private func optionGroupLabel(_ title: String) -> some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(theme.textSecondary)
    }

    private func optionCard(title: String, detail: String, systemImage: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button {
            selectionTick += 1
            withAnimation(.snappy) { action() }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: systemImage)
                    .font(.subheadline)
                    .foregroundStyle(selected ? theme.accent : theme.textSecondary)
                    .frame(width: 22)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(theme.textPrimary)
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(theme.textSecondary)
                }
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(theme.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(
                        selected ? AnyShapeStyle(theme.accentGradient) : AnyShapeStyle(theme.borderSubtle),
                        lineWidth: selected ? 2 : 1
                    )
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(title), \(detail)")
        .accessibilityAddTraits(selected ? .isSelected : [])
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
                    Text(viewModel.phase.title(for: viewModel.mode))
                        .font(.system(.title2, design: .rounded, weight: .bold))
                        .foregroundStyle(theme.textPrimary)
                        .id(viewModel.phase)
                        .transition(.opacity.combined(with: .offset(y: 8)))
                }
                Text(viewModel.phase.detail(for: viewModel.mode))
                    .font(.subheadline)
                    .foregroundStyle(theme.textSecondary)
                    .id(viewModel.phase)
                    .transition(.opacity)
                phaseSteps
                    .padding(.top, 6)
            }
            .animation(.smooth(duration: 0.45), value: viewModel.phase)
            .multilineTextAlignment(.center)

            Text("“\(viewModel.activeText)”")
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
