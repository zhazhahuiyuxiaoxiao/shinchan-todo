import Foundation

/// Learning state shares FocusController's single atomic archive writer.
@MainActor public extension FocusController {
    func dailyGoal(for task: TodoTask) -> Int? {
        if let preference = archive.preferences.first(where: { $0.key == FocusKey(task: task) }) { return preference.dailyGoalMinutes }
        return (try? FocusNotes.parse(task.notes).summary?.daily?.goalMinutes) ?? nil
    }
    func learningContext(for task: TodoTask) -> LearningContext? {
        if let preference = archive.preferences.first(where: { $0.key == FocusKey(task: task) }) { return preference.learning }
        return (try? FocusNotes.parse(task.notes).summary?.daily?.route?.context) ?? nil
    }
    func dailyProgress(for task: TodoTask) -> FocusDailyProgress {
        FocusDailyProgress(key: FocusKey(task: task), goal: dailyGoal(for: task), records: archive.records, now: date())
    }
    func route(for context: LearningContext) -> LearningRoute? { archive.routes.first { $0.id == context.routeID } }
    func stage(for context: LearningContext) -> LearningStage? { route(for: context)?.stages.first { $0.id == context.stageID } }
    func learningTitle(for task: TodoTask) -> String? {
        guard let context = learningContext(for: task) else { return nil }
        guard let route = route(for: context), let stage = stage(for: context) else { return "关联路线在本机不可用" }
        return "\(route.title) · \(stage.title)"
    }
    func suggestedStage(for task: TodoTask) -> LearningStage? {
        guard let context = learningContext(for: task), stage(for: context)?.completedAt != nil else { return nil }
        return route(for: context)?.nextStage(after: context.stageID)
    }
    @discardableResult func addRoute(title: String, id: UUID = UUID()) throws -> UUID {
        try checkLearningStorage()
        let name = try learningName(title)
        if let index = engine.archive.routes.firstIndex(where: { $0.id == id }) {
            engine.archive.routes[index].title = name
        } else { engine.archive.routes.append(LearningRoute(id: id, title: name)) }
        try saveLearningRoute(id)
        return id
    }
    func renameRoute(_ id: UUID, title: String) throws {
        try checkLearningStorage()
        guard let index = engine.archive.routes.firstIndex(where: { $0.id == id }) else { throw LearningError.missingStage }
        engine.archive.routes[index].title = try learningName(title); try saveLearningRoute(id)
    }
    @discardableResult func addStage(title: String, to routeID: UUID, id: UUID = UUID()) throws -> UUID {
        try checkLearningStorage()
        guard let index = engine.archive.routes.firstIndex(where: { $0.id == routeID }) else { throw LearningError.missingStage }
        let name = try learningName(title)
        if let stage = engine.archive.routes[index].stages.firstIndex(where: { $0.id == id }) {
            engine.archive.routes[index].stages[stage].title = name
        } else { engine.archive.routes[index].stages.append(LearningStage(id: id, title: name)) }
        try saveLearningRoute(routeID)
        return id
    }
    func renameStage(_ id: UUID, in routeID: UUID, title: String) throws {
        try checkLearningStorage()
        guard let route = engine.archive.routes.firstIndex(where: { $0.id == routeID }),
              let stage = engine.archive.routes[route].stages.firstIndex(where: { $0.id == id }) else { throw LearningError.missingStage }
        engine.archive.routes[route].stages[stage].title = try learningName(title); try saveLearningRoute(routeID)
    }
    func moveStage(_ id: UUID, in routeID: UUID, offset: Int) throws {
        try checkLearningStorage()
        guard let route = engine.archive.routes.firstIndex(where: { $0.id == routeID }),
              let stage = engine.archive.routes[route].stages.firstIndex(where: { $0.id == id }) else { throw LearningError.missingStage }
        let destination = stage + offset
        guard engine.archive.routes[route].stages.indices.contains(destination) else { return }
        let item = engine.archive.routes[route].stages.remove(at: stage)
        engine.archive.routes[route].stages.insert(item, at: destination)
        try saveLearningRoute(routeID)
    }
    func toggleStage(_ id: UUID, in routeID: UUID) throws {
        try checkLearningStorage()
        guard let route = engine.archive.routes.firstIndex(where: { $0.id == routeID }),
              let stage = engine.archive.routes[route].stages.firstIndex(where: { $0.id == id }) else { throw LearningError.missingStage }
        let completed = engine.archive.routes[route].stages[stage].completedAt != nil
        engine.archive.routes[route].stages[stage].completedAt = completed ? nil : date()
        try saveLearningRoute(routeID)
    }
    func setLearning(dailyGoal: Int?, context: LearningContext?, for task: TodoTask) throws {
        try checkLearningStorage()
        guard dailyGoal.map({ (1...1440).contains($0) }) ?? true else { throw LearningError.invalidGoal }
        if let context, stage(for: context) == nil { throw LearningError.missingStage }
        let checked = try todo.checkedFocusTask(task)
        let key = FocusKey(task: checked)
        if let run = archive.run, run.key == key, run.remaining > 0 { throw LearningError.activeRun }
        let minutes = minutes(for: checked)
        engine.archive.preferences.removeAll { $0.key == key }
        engine.archive.preferences.append(FocusPreference(key: key, minutes: minutes, dailyGoalMinutes: dailyGoal, learning: context))
        markPending(key); expectedTasks[key] = checked
        try saveLearning(); syncSummary(key, expected: checked)
    }
}

extension FocusController {
    func dailySummary(for task: TodoTask) -> FocusDailySummary {
        var routeSummary: LearningRouteSummary?
        if let context = learningContext(for: task) {
            if let route = route(for: context), let stage = stage(for: context) {
                routeSummary = LearningRouteSummary(context: context, routeTitle: route.title, stageTitle: stage.title,
                    completedStages: route.completedCount, totalStages: route.stages.count, stageCompleted: stage.completedAt != nil)
            } else {
                // Another Mac's association stays readable and inheritable; never invent a local route or merge history.
                routeSummary = (try? FocusNotes.parse(task.notes).summary?.daily?.route) ?? nil
            }
        }
        return FocusDailySummary(day: FocusNotes.dayString(date()), goalMinutes: dailyGoal(for: task), todayMinutes: dailyProgress(for: task).completedMinutes, route: routeSummary)
    }
    func refreshLearningDate() {
        guard todo.phase == .ready, !todo.busy, !storageBlocked else { return }
        let day = FocusNotes.dayString(date())
        let dateChanged = summaryDay != day
        summaryDay = day
        for task in todo.tasks where !task.completed {
            let key = FocusKey(task: task)
            let summary = (try? FocusNotes.parse(task.notes).summary) ?? nil
            guard archive.preferences.contains(where: { $0.key == key }) || archive.records.contains(where: { $0.key == key }) ||
                    summary != nil else { continue }
            // Apple can expose another native instance on the same day. Reset inherited counts immediately.
            guard dateChanged || summary?.occurrence != key.occurrence || summary?.daily?.day != day else { continue }
            // Do not automatically rebase/retry a previously conflicting summary.
            guard !archive.pendingSummaries.contains(key) else { continue }
            markPending(key); expectedTasks[key] = task
            if persist() { syncSummary(key, expected: task) }
        }
    }
    private func learningName(_ text: String) throws -> String {
        let title = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { throw LearningError.emptyTitle }
        return title
    }
    private func checkLearningStorage() throws {
        guard !storageBlocked else { throw FocusError.invalidFile }
    }
    private func saveLearningRoute(_ id: UUID) throws {
        // Queue related phone updates in the same archive as the route change, including failed local saves.
        let tasks = todo.tasks.filter { !$0.completed && learningContext(for: $0)?.routeID == id }
        for task in tasks {
            let key = FocusKey(task: task); markPending(key); expectedTasks[key] = task
        }
        try saveLearning()
        for task in tasks { syncSummary(FocusKey(task: task), expected: task) }
    }
}
