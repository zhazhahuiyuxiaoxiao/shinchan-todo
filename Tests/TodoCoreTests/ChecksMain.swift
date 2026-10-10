import Foundation
import TodoCore

@MainActor enum Checks {
    static var failures = 0
    static var cases = 0
    static func run(_ name: String, _ body: () async throws -> Void) async {
        cases += 1
        let before = failures
        do { try await body() } catch { failures += 1; print("FAIL \(name): \(error)") }
        print("\(before == failures ? "PASS" : "FAIL") \(name)")
    }
}
@MainActor func expect(_ condition: @autoclosure () -> Bool, file: StaticString = #fileID, line: UInt = #line) {
    if !condition() { Checks.failures += 1; print("  assertion failed: \(file):\(line)") }
}
@MainActor func expectThrows(_ expected: TodoError, file: StaticString = #fileID, line: UInt = #line, _ body: () throws -> Void) {
    do { try body(); Checks.failures += 1; print("  expected error \(expected) at \(file):\(line)") }
    catch { expect(error as? TodoError == expected, file: file, line: line) }
}
@MainActor func expectThrowsAsync(_ expected: TodoError, file: StaticString = #fileID, line: UInt = #line, _ body: () async throws -> Void) async {
    do { try await body(); Checks.failures += 1; print("  expected error \(expected) at \(file):\(line)") }
    catch { expect(error as? TodoError == expected, file: file, line: line) }
}

@main struct ChecksMain {
    @MainActor static func main() async {
        await Checks.run("today excludes completed and other days") { todayExcludesCompletedAndOtherDays() }
        await Checks.run("overdue uses calendar day") { overdueUsesCalendarDayNotCurrentHour() }
        await Checks.run("midnight updates today") { midnightUpdatesTheTodayBoundary() }
        await Checks.run("combined status priority notes search") { combinesStatusPriorityAndCaseInsensitiveNotesSearch() }
        await Checks.run("date priority ordering") { sortsDatesThenPriorityAndPlacesUndatedLast() }
        await Checks.run("completed view") { emptySearchKeepsAllAndCompletedViewFilters() }
        await Checks.run("statistics and empty ratio") { statisticsCountEntireInputAndHaveFiniteEmptyRatio() }
        await Checks.run("scoped read") { try await readsOnlyBoundList() }
        await Checks.run("cross-list safety") { await rejectsCrossListResultsAndMutations() }
        await Checks.run("conflict safety") { rejectsStaleEditsCompletionsAndDeletes() }
        await Checks.run("title validation") { try rejectsBlankTitleWithoutSavingAndTrimsValidTitle() }
        await Checks.run("revoked permission and missing list") { await deniesWritesWhenAccessRevokedOrListMissing() }
        await Checks.run("failed write preserves record") { preservesOriginalOnWriteFailure() }
        await Checks.run("edit complete restore delete") { try allowsEditsCompletionRestoreAndDeletionInBoundList() }
        await Checks.run("advanced fields preserved") { try doesNotChangeAdvancedDateOrNativePriorityWhenEditingNotes() }
        await Checks.run("failed save keeps draft") { await failedSaveKeepsDraftAndHasNoSuccessState() }
        await Checks.run("saved then failed refresh avoids duplicates") { await failedRefreshAfterWriteDoesNotInviteDuplicateSubmission() }
        await Checks.run("external refresh preserves dirty editor") { await refreshDoesNotOverwriteDirtyEditorOrItsRevision() }
        await Checks.run("switch requires discard") { switchingEditorsRequiresExplicitDiscard() }
        await Checks.run("denied authorization") { await authorizationDenialStopsAtDisconnectedState() }
        await Checks.run("read-only failure retains draft") { await readOnlyListStopsOperationsAndRetainsDraft() }
        await Checks.run("explicit reload fetches fresh content") { explicitReloadFetchesLatestBeforeDiscardingDraft() }
        await Checks.run("failed reload preserves draft") { failedExplicitReloadRetainsDraft() }
        await Checks.run("refresh races and disconnect") { await refreshRacesCannotOverwriteLatestState() }
        await Checks.run("moved task refused with scoped single read") { movedTaskCannotBeReloadedOrWritten() }
        await Checks.run("permission revoked during read") { await permissionRevokedWhileReadPendingIsRejected() }
        await Checks.run("daily requires date and supported rule") { dailyRequiresDateAndRejectsUnsupportedCreation() }
        await Checks.run("daily round trip and disable") { try await dailyRoundTripAndDisablePreserveDate() }
        await Checks.run("repeat advanced completed conflict scope") { try repeatChangesRespectAdvancedCompletedConflictAndScope() }
        await Checks.run("repeat draft survives write and conflict") { await repeatDraftSurvivesFailureAndCountsAsDirty() }
        await Checks.run("native repeat mapping") { try nativeRepeatMappingProtectsAdvancedRules() }
        await Checks.run("focus elapsed pause and exactly once completion") { focusUsesElapsedTimeAndFinishesOnce() }
        await Checks.run("focus rest abandon sleep and recovery") { focusRestAbandonAndRecovery() }
        await Checks.run("focus daily instances Monday stats and empty") { focusDailyInstancesAndStatistics() }
        await Checks.run("focus summary preserves Chinese notes and rejects corruption") { try focusSummaryPreservesNotesAndRejectsMalformedBlocks() }
        await Checks.run("focus file round trip corruption and failure") { try focusFileRoundTripAndCorruption() }
        await Checks.run("focus notes scope conflict advanced fields and dirty draft") { try focusSummaryServiceKeepsDraftAndOriginalFields() }
        await Checks.run("focus completion conflict retry and local write failure") { try await focusControllerCompletionFailureAndRetry() }
        await Checks.run("focus recovery corrupt file and task completion") { await focusControllerScopeRecoveryAndTaskLoss() }
        await Checks.run("focus stops after completed deleted refresh failure and revoked permission") { await focusStopsAfterSuccessfulMutationWithFailedRefresh() }
        await Checks.run("notification shutdown drains pending add without duplicate sound") { try await notificationShutdownDrainsInFlightAndAvoidsDoubleSound() }
        await Checks.run("notification finish invalidates delayed authorization schedule") { try await notificationCompletionBeforeAuthorizationPreventsLateAlert() }
        await Checks.run("focus reread cannot rebase dirty draft across concurrent external change") { try await focusSummaryRereadCannotAuthorizeOverwritingConcurrentChanges() }
        await Checks.run("focus duration manual input bounds and invalid text") { focusDurationTextRejectsInvalidInput() }
        await Checks.run("focus duration settings preserve active round and persist") { await focusDurationSettingsDoNotChangeActiveRun() }
        await Checks.run("timed daily remains recognized") { timedDailyIsStillRecognized() }
        await Checks.run("weekly displays repeat interval") { weeklyRepeatHasUsefulDescription() }
        await Checks.run("custom native rules preserve intervals weekdays month patterns and ends") { try nativeCustomRulesRoundTripWithoutLosingMeaning() }
        await Checks.run("unsupported repeat detail and write protection") { try unsupportedRecurrenceIsDescribedAndCannotBeReplaced() }
        await Checks.run("custom repeat rejects invalid input before saving") { customRepeatValidationRejectsInvalidFieldsBeforeWrite() }
        await Checks.run("timed repeat edit keeps fields and failure draft") { try await timedRepeatEditingKeepsDateAndSummaryAndConflictDraft() }
        await Checks.run("repeat end date covers full DST day") { try repeatEndDateIncludesFullDayAcrossDST() }
        await Checks.run("repeat presets positions and focus instances") { try repeatPresetsAndMonthlyPositionMapping() }
        await Checks.run("explicit draft reset invalidates editor inputs but refresh keeps them") { try await explicitDraftResetChangesEditorIdentityButBackgroundUpdatesDoNot() }
        print("\(Checks.cases) cases, \(Checks.failures) failed assertions")
        exit(Checks.failures == 0 ? 0 : 1)
    }
}
