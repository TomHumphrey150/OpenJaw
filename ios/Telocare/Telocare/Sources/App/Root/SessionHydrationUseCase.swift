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
        let firstPartyContent = await loadFirstPartyContent()
        let migrationResult = migrationPipeline.run(
            fetchedDocument: fetchedDocument,
            firstPartyContent: firstPartyContent
        )

        backfillCanonicalGraphIfMissing(migrationResult.canonicalBackfillDiagram)
        persistDormantGraphMigrationIfNeeded(migrationResult.dormantGraphMigrationDiagram)
        persistSleepAttributionMigrationIfNeeded(migrationResult.sleepAttributionMigrationPatch)

        let dashboardViewModel = dashboardFactory.makeDashboard(
            document: migrationResult.document,
            firstPartyContent: firstPartyContent,
            fallbackGraph: migrationResult.fallbackGraph
        )

        return SessionHydrationResult(
            dashboardViewModel: dashboardViewModel,
            currentUserEmail: session.email
        )
    }

    private func loadFirstPartyContent() async -> FirstPartyContentBundle {
        do {
            return try await userDataRepository.fetchFirstPartyContent()
        } catch {
            return .empty
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
