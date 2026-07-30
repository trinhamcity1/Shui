import FirebaseFirestore
import Foundation

protocol CategoryRepository {
    func list() async throws -> [Category]
}

struct FirestoreCategoryRepository: CategoryRepository {
    private let db: Firestore

    init(db: Firestore = FirebaseBootstrap.firestore) {
        self.db = db
    }

    func list() async throws -> [Category] {
        let snapshot = try await db.collection("categories")
            .whereField("isActive", isEqualTo: true)
            .order(by: "sortOrder")
            .getDocuments()
        return snapshot.decoded()
    }
}

final class InMemoryCategoryRepository: CategoryRepository {
    var categories: [Category]

    init(categories: [Category] = []) {
        self.categories = categories
    }

    func list() async throws -> [Category] {
        categories
    }
}
