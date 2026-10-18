import Foundation
import Observation

// Owns one explanation sheet's generation state, following ForecastViewModel's lifecycle pattern:
// one active attempt, source checks before generation and before publication, and late or
// obsolete results ignored even if the underlying work does not honour cancellation.
@MainActor @Observable
final class FinancialInsightViewModel {
    enum State: Equatable {
        case idle
        case generating
        case completed(ValidatedFinancialInsight)
        case unavailable(FinancialInsightAvailability)
        case failed(FinancialInsightFailure)
        case cancelled
        case stale
    }

    // Rejected responses allowed per sheet: the deterministic first attempt plus up to two
    // varied user retries. Every attempt passes the same validator; this only bounds retrying.
    // Transient failures such as a busy model do not count.
    static let maximumRejections = 3

    private(set) var state: State = .idle
    private(set) var activeAttemptID: UUID?
    private(set) var rejectedCount = 0

    func generate(_ request: FinancialInsightRequest, attemptID: UUID,
                  validateSource: @MainActor () throws -> Void,
                  service: any FinancialInsightGenerating) async {
        // No automatic regeneration, no duplicate work and no recovery from stale.
        switch state {
        case .stale, .completed, .generating, .failed(.noReliableExplanation): return
        case .idle, .unavailable, .failed, .cancelled: break
        }
        activeAttemptID = attemptID
        do {
            try validateSource()
            let availability = service.availability()
            guard availability == .available else {
                activeAttemptID = nil
                state = .unavailable(availability)
                return
            }
            try Task.checkCancellation()
            state = .generating
            // Greedy output never changes for the same prompt, so after a rejected response
            // the retry samples instead of reproducing the same rejection.
            let sampling: FinancialInsightSampling = rejectedCount == 0 ? .deterministic : .varied
            let insight: ValidatedFinancialInsight
            do {
                let generated = try await service.generate(for: request, sampling: sampling)
                // A dismissed, cancelled or replaced attempt must never publish.
                guard activeAttemptID == attemptID else { return }
                try Task.checkCancellation()
                try validateSource()
                insight = try FinancialInsightValidator.validate(generated, for: request)
            } catch FinancialInsightFailure.unusableResponse where activeAttemptID == attemptID {
                // One count per attempt, whether the service could not decode the response or the
                // validator rejected it. After the last permitted rejection, say so rather than
                // offer another Retry.
                rejectedCount += 1
                throw rejectedCount >= Self.maximumRejections
                    ? FinancialInsightFailure.noReliableExplanation : FinancialInsightFailure.unusableResponse
            }
            activeAttemptID = nil
            state = .completed(insight)
        } catch is CancellationError {
            guard activeAttemptID == attemptID else { return }
            activeAttemptID = nil
            state = .cancelled
        } catch let failure as FinancialInsightFailure {
            guard activeAttemptID == attemptID else { return }
            activeAttemptID = nil
            state = .failed(failure)
        } catch is FinancialInsightStaleSourceError {
            guard activeAttemptID == attemptID else { return }
            invalidate()
        } catch {
            guard activeAttemptID == attemptID else { return }
            activeAttemptID = nil
            state = .failed(.unexpected)
        }
    }

    func cancel() {
        activeAttemptID = nil
        if state == .generating { state = .cancelled }
    }

    // Withdraws any visible explanation; a stale sheet can only be closed.
    func invalidate() {
        activeAttemptID = nil
        state = .stale
    }
}
