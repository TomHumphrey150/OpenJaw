struct LoadDashboardSnapshotUseCase {
    private let loadSnapshot: () -> DashboardSnapshot

    init<Repository: DashboardRepository>(repository: Repository) {
        loadSnapshot = repository.loadDashboardSnapshot
    }

    func execute() -> DashboardSnapshot {
        loadSnapshot()
    }
}
