import Foundation
import DopagakiCore
import DopagakiPersistence

private struct PersistenceCheckFailure: Error, CustomStringConvertible {
    var description: String
}

private func requirePersistence(_ condition: Bool, _ message: String) throws {
    if !condition { throw PersistenceCheckFailure(description: message) }
}

func runPersistenceChecks() throws -> Int {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("dopagaki-verification-\(UUID())", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    let repository = StateRepository(directory: folder)
    let empty = try repository.load()
    try requirePersistence(empty.tasks.isEmpty && empty.sessions.isEmpty && empty.rewards.isEmpty && empty.medals.isEmpty, "new installation must not contain fake history")
    print("PASS persistence: empty installation")

    let now = Date(timeIntervalSince1970: 1_791_000_000)
    var state = AppState(settings: .init(aggregationTimeZoneID: "Asia/Tokyo"))
    state.saveTask(TaskDefinition(title: "英語", createdAt: now), on: now)
    let completed = state.occurrences[0].id
    _ = state.complete(occurrenceID: completed, at: now)
    state.saveTask(TaskDefinition(title: "読書", createdAt: now), on: now)
    let running = state.occurrences.first { $0.id != completed }!.id
    try requirePersistence(state.startFocus(occurrenceID: running, mode: .stopwatch, at: now), "start persisted session")
    try repository.save(state)
    var restored = try StateRepository(directory: folder).load()
    try requirePersistence(restored == state, "snapshot round-trip")
    try requirePersistence(restored.activeFocus?.elapsed(at: now.addingTimeInterval(60)) == 60, "running session after restart")
    try requirePersistence(restored.complete(occurrenceID: completed, at: now) == nil && restored.totalXP == 100, "reward dedup after restart")
    print("PASS persistence: restored focus and unique reward")

    let damaged = Data("original unreadable snapshot".utf8)
    try damaged.write(to: repository.stateURL)
    var rejected = false
    do { _ = try repository.load() } catch { rejected = true }
    try requirePersistence(rejected, "corrupt data must not silently load")
    let backup = try repository.preserveUnreadableSnapshot()
    try requirePersistence(try Data(contentsOf: backup) == damaged, "backup preserves source bytes")
    try repository.save(AppState())
    try requirePersistence(try Data(contentsOf: backup) == damaged, "new save preserves backup")
    print("PASS persistence: corruption preserved")

    let imageBytes = Data([1, 2, 3])
    let name = try repository.savePhoto(imageBytes)
    guard let photo = repository.photoURL(name) else { throw PersistenceCheckFailure(description: "stored photo missing") }
    try requirePersistence(try Data(contentsOf: photo) == imageBytes, "photo bytes retained")
    try requirePersistence(repository.photoURL("../state-v1.json") == nil && repository.photoURL("/etc/hosts") == nil, "photo path confinement")
    print("PASS persistence: photo path confinement")

    let blocked = folder.appendingPathComponent("blocked")
    let original = Data("keep me".utf8)
    try original.write(to: blocked)
    var writeRejected = false
    do { try StateRepository(directory: blocked).save(AppState()) } catch { writeRejected = true }
    try requirePersistence(writeRejected, "invalid destination must report failure")
    try requirePersistence(try Data(contentsOf: blocked) == original, "failed save preserves original")
    print("PASS persistence: failed save preserves data")
    return 5
}
