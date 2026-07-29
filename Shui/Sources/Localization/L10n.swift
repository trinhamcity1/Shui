import Foundation

/// Typed keys into `Localizable.strings`, so a typo is a compile error
/// instead of a silently-blank label.
enum L10n {
    // Common
    static let appName = "app_name"
    static let ok = "common_ok"
    static let cancel = "common_cancel"
    static let next = "common_next"
    static let back = "common_back"
    static let done = "common_done"
    static let skip = "common_skip"
    static let continueLabel = "common_continue"

    // Onboarding
    static let onboardingWelcomeTitle = "onboarding_welcome_title"
    static let onboardingWelcomeBody = "onboarding_welcome_body"
    static let onboardingChooseLanguageTitle = "onboarding_choose_language_title"
    static let onboardingNameTitle = "onboarding_name_title"
    static let onboardingNamePlaceholder = "onboarding_name_placeholder"
    static let onboardingStateTitle = "onboarding_state_title"
    static let onboardingStateBody = "onboarding_state_body"
    static let onboardingLocalOfficialsTitle = "onboarding_local_officials_title"
    static let onboardingLocalOfficialsBody = "onboarding_local_officials_body"
    static let onboardingSenator1 = "onboarding_senator1"
    static let onboardingSenator2 = "onboarding_senator2"
    static let onboardingRepresentative = "onboarding_representative"
    static let onboardingGovernor = "onboarding_governor"
    static let onboardingGoalTitle = "onboarding_goal_title"
    static let onboardingGoalBody = "onboarding_goal_body"
    static let onboardingGetStarted = "onboarding_get_started"

    // Home
    static let homeStartSession = "home_start_session"
    static let homeStreakLabel = "home_streak_label"
    static let homeTodaysSession = "home_todays_session"
    static let homeAllCaughtUp = "home_all_caught_up"
    static let homeMinutesToday = "home_minutes_today"
    static let homeTabHome = "home_tab_home"
    static let homeTabProgress = "home_tab_progress"
    static let homeTabSettings = "home_tab_settings"

    // Lesson
    static let lessonContinueToQuiz = "lesson_continue_to_quiz"
    static let lessonSkip = "lesson_skip"
    static let lessonReplay = "lesson_replay"
    static let lessonMenuTitle = "lesson_menu_title"
    static let lessonJumpToPart = "lesson_jump_to_part"
    static let lessonChapterPickerTitle = "lesson_chapter_picker_title"

    // Quiz
    static let quizSelectAnswer = "quiz_select_answer"
    static let quizSelectAnswerPlural = "quiz_select_answer_plural"
    static let quizSubmit = "quiz_submit"
    static let quizCorrect = "quiz_correct"
    static let quizIncorrect = "quiz_incorrect"
    static let quizCorrectAnswerWas = "quiz_correct_answer_was"
    static let quizNextQuestion = "quiz_next_question"
    static let quizFinishSession = "quiz_finish_session"
    static let quizNeedsProfileInfo = "quiz_needs_profile_info"
    static let quizGoToSettings = "quiz_go_to_settings"

    // Session summary
    static let summaryTitle = "summary_title"
    static let summaryQuestionsAnswered = "summary_questions_answered"
    static let summaryAccuracy = "summary_accuracy"
    static let summaryDone = "summary_done"

    // Progress
    static let progressTitle = "progress_title"
    static let progressMastered = "progress_mastered"
    static let progressLearning = "progress_learning"
    static let progressNew = "progress_new"
    static let progressCategoryBreakdown = "progress_category_breakdown"
    static let progressCurrentStreak = "progress_current_streak"
    static let progressLongestStreak = "progress_longest_streak"

    // Feed
    static let feedTab = "feed_tab"
    static let feedSwipeForNext = "feed_swipe_for_next"
    static let feedInfoButton = "feed_info_button"
    static let feedAskAI = "feed_ask_ai"

    // Info & Community
    static let infoExplanationTitle = "info_explanation_title"
    static let commentsTitle = "comments_title"
    static let commentsPlaceholder = "comments_placeholder"
    static let commentsSend = "comments_send"
    static let commentsReply = "comments_reply"
    static let commentsEmpty = "comments_empty"
    static let commentsGuestName = "comments_guest_name"

    // Sign-in & tiers
    static let signinTitle = "signin_title"
    static let signinBody = "signin_body"
    static let signinGoogle = "signin_google"
    static let signinFacebook = "signin_facebook"
    static let signinInstagram = "signin_instagram"
    static let signinLater = "signin_later"
    static let tierTitle = "tier_title"
    static let tierFreeTitle = "tier_free_title"
    static let tierFreeDesc = "tier_free_desc"
    static let tierProTitle = "tier_pro_title"
    static let tierProDesc = "tier_pro_desc"
    static let proBadge = "pro_badge"
    static let upgradeTitle = "upgrade_title"
    static let upgradeBody = "upgrade_body"
    static let upgradeCTA = "upgrade_cta"
    static let upgradeLater = "upgrade_later"

    // AI chat
    static let chatTitle = "chat_title"
    static let chatOpener = "chat_opener"
    static let chatPlaceholder = "chat_placeholder"

    // Pro analytics
    static let analyticsTitle = "analytics_title"
    static let analyticsLocked = "analytics_locked"

    // Settings
    static let settingsTitle = "settings_title"
    static let settingsLanguage = "settings_language"
    static let settingsDailyGoal = "settings_daily_goal"
    static let settingsLocalOfficials = "settings_local_officials"
    static let settingsAbout = "settings_about"
    static let settingsAboutBody = "settings_about_body"
}
