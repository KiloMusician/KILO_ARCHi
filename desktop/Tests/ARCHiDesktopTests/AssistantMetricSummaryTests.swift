import Testing
@testable import ARCHiDesktop

struct AssistantMetricSummaryTests {
    @Test func unknownZeroAndPartialReportsStayDifferent() {
        #expect(AssistantMetricSummary.tokens([], key: \.inputTokens) == "No local calls")
        #expect(AssistantMetricSummary.tokens([call(nil)], key: \.inputTokens) == "Unavailable")
        #expect(AssistantMetricSummary.tokens([call(0)], key: \.inputTokens) == "0")
        #expect(AssistantMetricSummary.tokens([call(42), call(nil)], key: \.inputTokens) == "42 known · 1/2 calls reported")
        #expect(AssistantMetricSummary.tokens([call(42), call(8)], key: \.inputTokens) == "50")
    }

    @Test func rejectedRoleStillAccountsForReportedWorkAndBrokenTotalsCannotOverflow() {
        var rejected = call(20)
        rejected.outcome = .failed
        #expect(AssistantMetricSummary.tokens([rejected], key: \.inputTokens) == "20")
        #expect(AssistantMetricSummary.tokens([call(Int.max), call(1)], key: \.inputTokens) == "Unavailable · invalid total")
        #expect(AssistantMetricSummary.tokens([call(-1)], key: \.inputTokens) == "Unavailable · invalid total")
        #expect(AssistantMetricSummary.duration(nil) == "Unavailable")
        #expect(AssistantMetricSummary.duration(0) == "0.000 s")
        #expect(AssistantMetricSummary.duration(1_500_000_000) == "1.500 s")
    }

    private func call(_ count: Int?) -> HamptonInvocationReceipt {
        HamptonInvocationReceipt(id: "fixture", role: .reasoning, inputDigest: "a", systemDigest: "b",
            schemaDigest: "c", metrics: count.map { LocalInferenceMetrics(inputTokens: $0) })
    }
}
