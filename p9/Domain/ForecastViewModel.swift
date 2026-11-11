import Foundation
import Observation

//This class manages the Monte Carlo forecasting process.
//when a user starts a forecast, this class handles starting the calculation,
//updating the progress percentage, receiving the result, cancelling, and detecting outdated results

@MainActor @Observable
final class ForecastViewModel {
    enum State: Equatable {
        case idle
        case running(Int)
        case completed(ForecastResult)
        case failed(String)
        case cancelled
        case stale
    }

    typealias Runner = @Sendable (ForecastRequest, ForecastEngine.Progress) async throws -> ForecastResult
    private(set) var state: State = .idle
    private(set) var activeRequestID: UUID?

    func run(_ request: ForecastRequest, validateSource: @MainActor () throws -> Void,
             runner: Runner = { try await ForecastEngine.run(request: $0, progress: $1) }) async {
        if case .completed(let result) = state, result.request.id == request.id { return }
        guard state != .stale else { return }
        activeRequestID = request.id
        do {
            try validateSource()
            try Task.checkCancellation()
            state = .running(0)
            let result = try await runner(request) { [weak self] percent in
                await self?.acceptProgress(percent, requestID: request.id)
            }
            try Task.checkCancellation()
            guard activeRequestID == request.id else { return }
            try validateSource()
            state = .completed(result)
        } catch is CancellationError {
            guard activeRequestID == request.id else { return }
            state = .cancelled
        } catch {
            guard activeRequestID == request.id else { return }
            if error as? ForecastError == .staleSource {
                invalidate()
            } else {
                state = .failed(error.localizedDescription)
            }
        }
    }

    func acceptProgress(_ percent: Int, requestID: UUID) {
        guard activeRequestID == requestID, case .running(let previous) = state,
              percent > previous else { return }
        state = .running(min(percent, 100))
    }

    func cancel() {
        activeRequestID = nil
        if case .running = state { state = .cancelled }
    }

    func invalidate() {
        activeRequestID = nil
        state = .stale
    }
}
