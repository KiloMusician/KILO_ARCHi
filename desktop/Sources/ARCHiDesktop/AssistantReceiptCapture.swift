import Foundation

@MainActor
extension CompanionStore {
    /// Record the existing lesson filter's omissions at Send. IDs only; this
    /// does not add a lesson to either provider's input or remember a withdrawal.
    func lessonOmissions(for request: AssistantRequest, now: Date = Date()) -> [AssistantEvidenceOmission] {
        let included = Set(request.localLessons.map(\.modelID))
        return keptLessons.compactMap { lesson in
            guard lesson.isValid, !included.contains(LessonSnapshot(lesson: lesson).modelID) else { return nil }
            let reason: AssistantEvidenceOmission.Reason
            if let expiry = lesson.expiresAt, expiry <= now { reason = .expired }
            else if let source = lesson.source,
                    source.name != request.sourceName || source.digest != LessonSource.digest(of: request.sourceText) {
                reason = .otherSource
            } else { reason = .unmatched }
            return AssistantEvidenceOmission(kind: .lessons, reason: reason,
                ids: [LessonSnapshot(lesson: lesson).modelID], count: 1)
        }
    }

    func capturedEvidence(_ evidence: AssistantEvidenceReceipt?, for provider: AssistantProvider) -> AssistantEvidenceReceipt? {
        guard provider == .qwen, var evidence else { return nil }
        evidence.omissions += compareResults[provider]?.receipt?.localLessonOmissions ?? []
        return evidence
    }
}
