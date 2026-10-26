import Testing
@testable import SpikeCore

struct OperationBudgetTests {
    @Test func spendingUpToTheCapIsAllowed() {
        var budget = OperationBudget(experiment: .b3)
        for _ in 0..<OperationBudget.Experiment.b3.cap {
            let allowed = budget.spend()
            #expect(allowed)
        }
        #expect(budget.remaining == 0)
    }

    @Test func theFirstSpendBeyondTheCapIsRefused() {
        var budget = OperationBudget(experiment: .n1)
        for _ in 0..<OperationBudget.Experiment.n1.cap { _ = budget.spend() }
        let beyond = budget.spend()
        #expect(!beyond)
        #expect(budget.used == OperationBudget.Experiment.n1.cap)
    }

    @Test func spendingSeveralAtOnceCannotOvershoot() {
        var budget = OperationBudget(experiment: .n2)
        let overshoot = budget.spend(OperationBudget.Experiment.n2.cap + 1)
        #expect(!overshoot)
        #expect(budget.used == 0)
    }

    @Test func capsMatchTheConsentTable() {
        // sprint-0-detail.md §6 硬上限表
        let expected: [OperationBudget.Experiment: Int] = [
            .preflight: 40, .b3: 60, .b2: 220, .b4: 100, .b6Baseline: 110, .b6Loaded: 170,
            .b5: 320, .b5Play: 70, .b1: 30, .n1: 4, .n2: 8, .fp01: 30, .restore: 70,
        ]
        for (experiment, cap) in expected { #expect(experiment.cap == cap, "\(experiment)") }
        #expect(Set(expected.keys) == Set(OperationBudget.Experiment.allCases))
    }
}
