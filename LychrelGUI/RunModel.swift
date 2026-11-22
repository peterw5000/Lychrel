import AppKit
import CoreGraphics
import Foundation
import LychrelKit
import Observation

struct RunSummary {
    let lowerBound: Int
    let upperBound: Int
    let total: Int
    let checked: Int
    let maxIterations: Int
    let algorithm: Algorithm
    let palindromes: Int
    let exceeded: Int
    let wasCancelled: Bool
    let calc: Duration
    let sort: Duration?
    let write: Duration?
    let csvPath: String?
    let csvError: String?
}

@MainActor
@Observable
final class RunModel {
    private(set) var isRunning = false
    private(set) var isCancelling = false
    private(set) var completed = 0
    private(set) var total = 0
    private(set) var currentNumber = 0
    private(set) var exceeded = 0
    private(set) var summary: RunSummary?

    // Spiral visualisation of the last completed run. Rendered once the run
    // finishes; a live mode would re-render from partial results instead.
    private(set) var spiral: CGImage?
    private(set) var spiralError: String?

    private var cancellation: CancellationFlag?
    private var runID = 0

    func start(lowerBound: Int, upperBound: Int, maxIterations: Int, algorithm: Algorithm, csvPath: String) {
        runID += 1
        let id = runID
        let flag = CancellationFlag()
        cancellation = flag

        completed = 0
        total = upperBound - lowerBound + 1
        currentNumber = 0
        exceeded = 0
        summary = nil
        spiral = nil
        spiralError = nil
        isRunning = true
        isCancelling = false

        let clock = ContinuousClock()
        // Render the spiral in the display's colour space so showing it
        // doesn't require a full-bitmap conversion on the main thread.
        let displayColorSpace = NSScreen.main?.colorSpace?.cgColorSpace

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            // Snapshot the weak reference into a constant so the nested Tasks
            // capture an immutable value rather than the mutable weak variable.
            let model = self
            var outcome: RunOutcome!
            let calcDuration = clock.measure {
                outcome = runChecks(lowerBound: lowerBound, upperBound: upperBound, maxIterations: maxIterations, algorithm: algorithm, cancellation: flag) { progress in
                    Task { @MainActor in
                        model?.apply(progress, id: id)
                    }
                }
            }

            var sortDuration: Duration?
            var writeDuration: Duration?
            var csvError: String?
            var results = outcome.results

            if !outcome.wasCancelled {
                sortDuration = clock.measure {
                    results.sort { $0.number < $1.number }
                }
                writeDuration = clock.measure {
                    do {
                        try writeCSV(results, toPath: csvPath)
                    } catch {
                        csvError = error.localizedDescription
                    }
                }
            }

            // A cancelled run leaves unchecked placeholders, which would draw
            // as non-Lychrel, so only visualise complete runs.
            var spiral: CGImage?
            var spiralError: String?
            if !outcome.wasCancelled {
                do {
                    spiral = try SpiralRenderer.render(lychrel: results.map(\.exceededMaxIter), colorSpace: displayColorSpace)
                } catch {
                    spiralError = error.localizedDescription
                }
            }

            let summary = RunSummary(
                lowerBound: lowerBound,
                upperBound: upperBound,
                total: upperBound - lowerBound + 1,
                checked: outcome.completed,
                maxIterations: maxIterations,
                algorithm: algorithm,
                palindromes: outcome.palindromes,
                exceeded: outcome.exceeded,
                wasCancelled: outcome.wasCancelled,
                calc: calcDuration,
                sort: sortDuration,
                write: writeDuration,
                csvPath: outcome.wasCancelled ? nil : csvPath,
                csvError: csvError
            )

            // Capture the final values by copy so the main-actor Task doesn't
            // reference the mutable locals.
            Task { @MainActor [spiral, spiralError] in
                model?.finish(summary, spiral: spiral, spiralError: spiralError, id: id)
            }
        }
    }

    func cancel() {
        guard isRunning else { return }
        cancellation?.cancel()
        isCancelling = true
    }

    private func apply(_ progress: RunProgress, id: Int) {
        guard id == runID, isRunning, progress.completed > completed else { return }
        completed = progress.completed
        total = progress.total
        currentNumber = progress.currentNumber
        exceeded = progress.exceeded
    }

    private func finish(_ summary: RunSummary, spiral: CGImage?, spiralError: String?, id: Int) {
        guard id == runID else { return }
        self.summary = summary
        self.spiral = spiral
        self.spiralError = spiralError
        isRunning = false
        isCancelling = false
    }
}
