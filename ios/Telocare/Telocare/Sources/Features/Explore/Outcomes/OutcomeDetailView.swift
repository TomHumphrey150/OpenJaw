import SwiftUI

struct OutcomeDetailView: View {
    let record: OutcomeRecord
    let outcomesMetadata: OutcomesMetadata

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: TelocareTheme.Spacing.md) {
                Text("Night \(record.id)")
                    .font(.largeTitle.bold())
                    .foregroundStyle(TelocareTheme.charcoal)
                    .fixedSize(horizontal: false, vertical: true)

                measurementsCard
                interpretationCard

                if !outcomeNodeEvidence.isEmpty {
                    evidenceCard
                }
            }
            .padding(TelocareTheme.Spacing.md)
        }
        .background(TelocareTheme.sand.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Measurements Card

    @ViewBuilder
    private var measurementsCard: some View {
        WarmCard {
            VStack(alignment: .leading, spacing: TelocareTheme.Spacing.sm) {
                WarmSectionHeader(title: "Measurements")

                DetailRow(label: "Night", value: record.id)
                DetailRow(label: "Arousal rate/hour", value: formatted(record.microArousalRatePerHour))
                DetailRow(label: "Arousal count", value: formatted(record.microArousalCount))
                DetailRow(label: "Confidence", value: formatted(record.confidence))
                DetailRow(label: "Source", value: record.source ?? "Unknown")
            }
        }
    }

    // MARK: - Interpretation Card

    @ViewBuilder
    private var interpretationCard: some View {
        WarmCard {
            VStack(alignment: .leading, spacing: TelocareTheme.Spacing.sm) {
                WarmSectionHeader(title: "How to read this")

                if metricsForDisplay.isEmpty {
                    Text("Outcome metadata is not available yet.")
                        .font(TelocareTheme.Typography.body)
                        .foregroundStyle(TelocareTheme.warmGray)
                } else {
                    ForEach(metricsForDisplay, id: \.id) { metric in
                        VStack(alignment: .leading, spacing: TelocareTheme.Spacing.xs) {
                            Text(metric.label)
                                .font(TelocareTheme.Typography.headline)
                                .foregroundStyle(TelocareTheme.charcoal)
                            Text(metric.description)
                                .font(TelocareTheme.Typography.caption)
                                .foregroundStyle(TelocareTheme.warmGray)

                            HStack(spacing: TelocareTheme.Spacing.md) {
                                WarmChip(text: metric.unit)
                                WarmChip(text: metric.direction.replacingOccurrences(of: "_", with: " "))
                            }
                        }
                        .padding(.vertical, TelocareTheme.Spacing.xs)

                        if metric.id != metricsForDisplay.last?.id {
                            Divider()
                                .background(TelocareTheme.peach)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Evidence Card

    @ViewBuilder
    private var evidenceCard: some View {
        WarmCard {
            VStack(alignment: .leading, spacing: TelocareTheme.Spacing.sm) {
                WarmSectionHeader(title: "Outcome pathway evidence")

                ForEach(outcomeNodeEvidence) { node in
                    VStack(alignment: .leading, spacing: TelocareTheme.Spacing.xs) {
                        Text(node.label)
                            .font(TelocareTheme.Typography.headline)
                            .foregroundStyle(TelocareTheme.charcoal)

                        if let evidence = node.evidence {
                            DetailRow(label: "Evidence", value: evidence)
                        }
                        if let stat = node.stat {
                            DetailRow(label: "Statistic", value: stat)
                        }
                        if let citation = node.citation {
                            Text(citation)
                                .font(TelocareTheme.Typography.caption)
                                .foregroundStyle(TelocareTheme.warmGray)
                                .italic()
                        }
                        if let mechanism = node.mechanism {
                            Text(mechanism)
                                .font(TelocareTheme.Typography.body)
                                .foregroundStyle(TelocareTheme.charcoal)
                        }
                    }
                    .padding(.vertical, TelocareTheme.Spacing.xs)

                    if node.id != outcomeNodeEvidence.last?.id {
                        Divider()
                            .background(TelocareTheme.peach)
                    }
                }
            }
        }
    }

    private func formatted(_ value: Double?) -> String {
        guard let value else { return "Not recorded" }
        return String(format: "%.2f", value)
    }

    private var metricsForDisplay: [OutcomeMetricDefinition] {
        outcomesMetadata.metrics.filter {
            $0.id == "microArousalRatePerHour"
                || $0.id == "microArousalCount"
                || $0.id == "confidence"
        }
    }

    private var outcomeNodeEvidence: [OutcomeNodeMetadata] {
        outcomesMetadata.nodes
    }
}

