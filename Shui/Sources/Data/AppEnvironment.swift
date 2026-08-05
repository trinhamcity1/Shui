import Combine
import Foundation

/// One object holding every repository, injected once at the root so views,
/// previews, and tests can swap in fakes without touching call sites.
@MainActor
final class AppEnvironment: ObservableObject {
    let categories: CategoryRepository
    let topics: TopicRepository
    let videos: VideoRepository
    let quizzes: QuizRepository
    let progress: ProgressRepository
    let social: SocialRepository
    let users: UserRepository
    let uploads: UploadRepository
    let aiTutor: AITutorRepository
    let auth: AuthRepository
    let admin: AdminRepository

    /// The signed-in learner's server profile — reactive so the whole app
    /// (tab bar gating, Profile header, guest-only prompts) updates the
    /// moment a sign-in, sign-out, or account link completes, instead of
    /// each screen re-fetching independently. `nil` only during the brief
    /// window before `bootstrapSession()` finishes on launch.
    @Published private(set) var currentUser: UserAccount?

    /// Read from the ID token's custom claim, not from `currentUser.role`
    /// (a display mirror). Drives whether Creator mode is reachable at all —
    /// note that hiding the entry point is a UX decision, not the security
    /// boundary: rules and callables enforce the real one server-side.
    @Published private(set) var role: UserAccount.Role = .learner

    var isGuest: Bool { auth.isGuest }
    var isCreator: Bool { role == .creator || role == .admin }
    var isAdmin: Bool { role == .admin }

    init(
        categories: CategoryRepository,
        topics: TopicRepository,
        videos: VideoRepository,
        quizzes: QuizRepository,
        progress: ProgressRepository,
        social: SocialRepository,
        users: UserRepository,
        uploads: UploadRepository,
        aiTutor: AITutorRepository,
        auth: AuthRepository,
        admin: AdminRepository
    ) {
        self.categories = categories
        self.topics = topics
        self.videos = videos
        self.quizzes = quizzes
        self.progress = progress
        self.social = social
        self.users = users
        self.uploads = uploads
        self.aiTutor = aiTutor
        self.auth = auth
        self.admin = admin
    }

    static func live() -> AppEnvironment {
        AppEnvironment(
            categories: FirestoreCategoryRepository(),
            topics: FirestoreTopicRepository(),
            videos: FirestoreVideoRepository(),
            quizzes: FirestoreQuizRepository(),
            progress: FirestoreProgressRepository(),
            social: FirestoreSocialRepository(),
            users: FirestoreUserRepository(),
            uploads: FirebaseUploadRepository(),
            aiTutor: FirestoreAITutorRepository(),
            auth: FirebaseAuthRepository(),
            admin: FirebaseAdminRepository()
        )
    }

    static func preview() -> AppEnvironment {
        AppEnvironment(
            categories: InMemoryCategoryRepository(),
            topics: InMemoryTopicRepository(),
            videos: InMemoryVideoRepository(),
            quizzes: InMemoryQuizRepository(),
            progress: InMemoryProgressRepository(),
            social: InMemorySocialRepository(),
            users: InMemoryUserRepository(),
            uploads: InMemoryUploadRepository(),
            aiTutor: InMemoryAITutorRepository(),
            auth: InMemoryAuthRepository(),
            admin: InMemoryAdminRepository()
        )
    }

    // MARK: - Session

    /// Ensures someone is signed in (anonymous if no session exists yet),
    /// makes sure their `users/{uid}` document exists, and publishes it.
    /// Called once at launch; safe to call again after sign-out since it
    /// re-establishes a guest session rather than leaving the app in a
    /// signed-out limbo the rest of the UI was never designed to handle.
    func bootstrapSession() async {
        try? await auth.signInAnonymouslyIfNeeded()
        try? await users.createProfileIfNeeded(
            displayName: "Learner", photoURL: nil, authProviders: ["anonymous"], isGuest: true
        )
        await refreshCurrentUser()
        await refreshRole(forceRefresh: false)
    }

    func refreshCurrentUser() async {
        currentUser = try? await users.currentUser()
    }

    /// Called on launch (cached token is fine) and again on every foreground
    /// with `forceRefresh: true`. Custom claims are baked into the ID token
    /// when it's minted, so a role granted while the app was backgrounded
    /// stays invisible for up to an hour unless the token is re-minted —
    /// forcing it here is what satisfies "appears without a reinstall"
    /// (prompts/phase-05-creator-mode.md §1).
    func refreshRole(forceRefresh: Bool) async {
        role = await auth.roleClaim(forceRefresh: forceRefresh)
    }
}
