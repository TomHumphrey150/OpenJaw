import Foundation

struct SessionHydrationResult {
    let dashboardViewModel: AppViewModel
    let currentUserEmail: String?
}

protocol SessionHydrationUseCase {
    @MainActor
    func hydrate(session: AuthSession) async throws -> SessionHydrationResult
}

struct DefaultSessionHydrationUseCase: SessionHydrationUseCase {
    private let userDataRepository: UserDataRepository
    private let migrationPipeline: UserDataMigrationPipeline
    private let dashboardFactory: RootDashboardFactory

    init(
        userDataRepository: UserDataRepository,
        migrationPipeline: UserDataMigrationPipeline,
        dashboardFactory: RootDashboardFactory
    ) {
        self.userDataRepository = userDataRepository
        self.migrationPipeline = migrationPipeline
        self.dashboardFactory = dashboardFactory
    }

    @MainActor
    func hydrate(session: AuthSession) async throws -> SessionHydrationResult {
        let fetchedDocument = try await userDataRepository.fetch(userID: session.userID)
        let firstPartyContent = try await loadFirstPartyContent(userID: session.userID)
        let migrationResult = migrationPipeline.run(
            fetchedDocument: fetchedDocument,
            firstPartyContent: firstPartyContent
        )

        backfillCanonicalGraphIfMissing(migrationResult.canonicalBackfillDiagram)
        persistDormantGraphMigrationIfNeeded(migrationResult.dormantGraphMigrationDiagram)
        persistSleepAttributionMigrationIfNeeded(migrationResult.sleepAttributionMigrationPatch)

        let dashboardViewModel = dashboardFactory.makeDashboard(
            document: migrationResult.document,
            firstPartyContent: firstPartyContent
        )

        return SessionHydrationResult(
            dashboardViewModel: dashboardViewModel,
            currentUserEmail: session.email
        )
    }

    private func loadFirstPartyContent(userID: UUID) async throws -> FirstPartyContentBundle {
        let content = try await userDataRepository.fetchFirstPartyContent(userID: userID)
        try validate(content: content)
        return content
    }

    private func validate(content: FirstPartyContentBundle) throws {
        guard content.graphData != nil else {
            throw SessionHydrationContentError.missingRequiredContent(
                contentType: "graph",
                contentKey: "canonical_causal_graph"
            )
        }

        guard content.foundationCatalog != nil else {
            throw SessionHydrationContentError.missingRequiredContent(
                contentType: "planning",
                contentKey: "foundation_v1_catalog"
            )
        }

        guard content.planningPolicy != nil else {
            throw SessionHydrationContentError.missingRequiredContent(
                contentType: "planning",
                contentKey: "planner_policy_v1"
            )
        }
    }

    private func backfillCanonicalGraphIfMissing(_ canonicalDiagram: CustomCausalDiagram?) {
        guard let canonicalDiagram else {
            return
        }

        let repository = userDataRepository
        Task.detached {
            do {
                _ = try await repository.backfillDefaultGraphIfMissing(
                    canonicalGraph: canonicalDiagram.graphData,
                    lastModified: canonicalDiagram.lastModified ?? timestampNow()
                )
            } catch {
            }
        }
    }

    private func persistDormantGraphMigrationIfNeeded(_ migratedDiagram: CustomCausalDiagram?) {
        guard let migratedDiagram else {
            return
        }

        let repository = userDataRepository
        Task.detached {
            do {
                _ = try await repository.upsertUserDataPatch(.customCausalDiagram(migratedDiagram))
            } catch {
            }
        }
    }

    private func persistSleepAttributionMigrationIfNeeded(_ patch: UserDataPatch?) {
        guard let patch else {
            return
        }

        let repository = userDataRepository
        Task.detached {
            do {
                _ = try await repository.upsertUserDataPatch(patch)
            } catch {
            }
        }
    }

    nonisolated private func timestampNow() -> String {
        ISO8601DateFormatter().string(from: Date())
    }
}

private enum SessionHydrationContentError: LocalizedError {
    case missingRequiredContent(contentType: String, contentKey: String)

    var errorDescription: String? {
        switch self {
        case .missingRequiredContent(let contentType, let contentKey):
            return "Missing required Supabase content: \(contentType)/\(contentKey)."
        }
    }
}
