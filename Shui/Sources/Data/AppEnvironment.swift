import Combine
import Foundation

/// One object holding every repository, injected once at the root so views,
/// previews, and tests can swap in fakes without touching call sites.
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

    init(
        categories: CategoryRepository,
        topics: TopicRepository,
        videos: VideoRepository,
        quizzes: QuizRepository,
        progress: ProgressRepository,
        social: SocialRepository,
        users: UserRepository,
        uploads: UploadRepository,
        aiTutor: AITutorRepository
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
            aiTutor: UnimplementedAITutorRepository()
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
            aiTutor: UnimplementedAITutorRepository()
        )
    }
}
