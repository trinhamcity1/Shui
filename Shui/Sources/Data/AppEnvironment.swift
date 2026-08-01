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

    /// The signed-in learner's server profile — reactive so the whole app
    /// (tab bar gating, Profile header, guest-only prompts) updates the
    /// moment a sign-in, sign-out, or account link completes, instead of
    /// each screen re-fetching independently. `nil` only during the brief
    /// window before `bootstrapSession()` finishes on launch.
    @Published private(set) var currentUser: UserAccount?

    var isGuest: Bool { auth.isGuest }

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
        auth: AuthRepository
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
            aiTutor: UnimplementedAITutorRepository(),
            auth: FirebaseAuthRepository()
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
            aiTutor: UnimplementedAITutorRepository(),
            auth: InMemoryAuthRepository()
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
    }

    func refreshCurrentUser() async {
        currentUser = try? await users.currentUser()
    }
}
