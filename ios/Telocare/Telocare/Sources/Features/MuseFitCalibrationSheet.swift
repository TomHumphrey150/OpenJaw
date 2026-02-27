import SwiftUI

struct MuseFitCalibrationSheet: View {
    let diagnostics: MuseLiveDiagnostics?
    let readyStreakSeconds: Int
    let requiredReadySeconds: Int
    let primaryBlockerText: String?
    let canStartWhenReady: Bool
    let canStartWithOverride: Bool
    let canExportSetupDiagnostics: Bool
    let onClose: () -> Void
    let onStartWhenReady: () -> Void
    let onStartWithOverride: () -> Void
    let onExportSetupDiagnostics: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: TelocareTheme.Spacing.md) {
                    Text("Muse fit calibration")
                        .font(TelocareTheme.Typography.headline)
                        .foregroundStyle(TelocareTheme.charcoal)

                    Text(fitStatusText)
                        .font(TelocareTheme.Typography.caption)
                        .foregroundStyle(TelocareTheme.warmGray)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier(AccessibilityID.exploreMuseFitModalStatusText)

                    Text("Why not ready now: \(fitPrimaryBlockerMessage)")
                        .font(TelocareTheme.Typography.caption)
                        .foregroundStyle(fitPrimaryBlockerColor)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier(AccessibilityID.exploreMuseFitModalPrimaryBlockerText)

                    Text("Ready streak: \(readyStreakSeconds)/\(requiredReadySeconds) seconds.")
                        .font(TelocareTheme.Typography.caption)
                        .foregroundStyle(TelocareTheme.charcoal)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier(AccessibilityID.exploreMuseFitModalReadyStreakText)

                    diagnosisSection
                    connectionHealthSection
                    signalHealthSection
                    troubleshootingSection
                    readinessChecksSection
                    sensorStatusSection

                    if let fitGuidanceText = diagnostics?.fitGuidance.guidanceText {
                        Text(fitGuidanceText)
                            .font(TelocareTheme.Typography.caption)
                            .foregroundStyle(TelocareTheme.warmGray)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Button(action: onStartWhenReady) {
                        Text("Start recording (fit ready)")
                            .font(TelocareTheme.Typography.body)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(TelocareTheme.success)
                    .disabled(!canStartWhenReady)
                    .accessibilityIdentifier(AccessibilityID.exploreMuseFitModalStartReadyButton)

                    Button(action: onStartWithOverride) {
                        Text("Start anyway (low reliability)")
                            .font(TelocareTheme.Typography.body)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(TelocareTheme.coral)
                    .disabled(!canStartWithOverride)
                    .accessibilityIdentifier(AccessibilityID.exploreMuseFitModalStartOverrideButton)

                    Button(action: onExportSetupDiagnostics) {
                        Text("Export setup diagnostics (full zip)")
                            .font(TelocareTheme.Typography.body)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(TelocareTheme.charcoal)
                    .disabled(!canExportSetupDiagnostics)
                    .accessibilityIdentifier(AccessibilityID.exploreMuseFitModalExportSetupButton)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, TelocareTheme.Spacing.md)
                .padding(.vertical, TelocareTheme.Spacing.lg)
            }
            .background(TelocareTheme.sand.ignoresSafeArea())
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close", action: onClose)
                        .accessibilityIdentifier(AccessibilityID.exploreMuseFitModalCloseButton)
                }
            }
        }
        .accessibilityIdentifier(AccessibilityID.exploreMuseFitModal)
    }

    @ViewBuilder
    private var diagnosisSection: some View {
        Text("Likely issue: \(diagnosisText)")
            .font(TelocareTheme.Typography.caption)
            .foregroundStyle(TelocareTheme.charcoal)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityIdentifier(AccessibilityID.exploreMuseFitModalDiagnosisText)
    }

    @ViewBuilder
    private var connectionHealthSection: some View {
        Text(connectionHealthText)
            .font(TelocareTheme.Typography.caption)
            .foregroundStyle(TelocareTheme.warmGray)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityIdentifier(AccessibilityID.exploreMuseFitModalConnectionHealthText)
    }

    @ViewBuilder
    private var signalHealthSection: some View {
        Text(signalHealthText)
            .font(TelocareTheme.Typography.caption)
            .foregroundStyle(TelocareTheme.warmGray)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityIdentifier(AccessibilityID.exploreMuseFitModalSignalHealthText)
    }

    @ViewBuilder
    private var troubleshootingSection: some View {
        Text("If readings stay low")
            .font(TelocareTheme.Typography.body)
            .foregroundStyle(TelocareTheme.charcoal)

        Text(troubleshootingSummaryText)
            .font(TelocareTheme.Typography.caption)
            .foregroundStyle(TelocareTheme.warmGray)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityIdentifier(AccessibilityID.exploreMuseFitModalTroubleshootingSummaryText)

        Text(troubleshootingActionsText)
            .font(TelocareTheme.Typography.caption)
            .foregroundStyle(TelocareTheme.warmGray)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityIdentifier(AccessibilityID.exploreMuseFitModalTroubleshootingActionsText)

        Text(overnightTipsText)
            .font(TelocareTheme.Typography.caption)
            .foregroundStyle(TelocareTheme.warmGray)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityIdentifier(AccessibilityID.exploreMuseFitModalOvernightTipsText)
    }

    @ViewBuilder
    private var readinessChecksSection: some View {
        let checks = readinessChecks

        Text("Readiness checks")
            .font(TelocareTheme.Typography.body)
            .foregroundStyle(TelocareTheme.charcoal)

        VStack(alignment: .leading, spacing: TelocareTheme.Spacing.xs) {
            ForEach(Array(checks.enumerated()), id: \.offset) { _, check in
                Text("\(check.title): \(check.statusText). \(check.detail)")
                    .font(TelocareTheme.Typography.caption)
                    .foregroundStyle(TelocareTheme.warmGray)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityIdentifier(AccessibilityID.exploreMuseFitModalReadinessChecksText)
    }

    @ViewBuilder
    private var sensorStatusSection: some View {
        Text("Sensor status")
            .font(TelocareTheme.Typography.body)
            .foregroundStyle(TelocareTheme.charcoal)

        if sensorStatuses.isEmpty {
            Text("No per-sensor fit data yet.")
                .font(TelocareTheme.Typography.caption)
                .foregroundStyle(TelocareTheme.warmGray)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier(AccessibilityID.exploreMuseFitModalSensorStatusText)
        } else {
            VStack(alignment: .leading, spacing: TelocareTheme.Spacing.xs) {
                ForEach(sensorStatuses, id: \.sensor.rawValue) { status in
                    Text(sensorRowText(for: status))
                        .font(TelocareTheme.Typography.caption)
                        .foregroundStyle(TelocareTheme.warmGray)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .accessibilityIdentifier(AccessibilityID.exploreMuseFitModalSensorStatusText)
        }
    }

    private var sensorStatuses: [MuseSensorFitStatus] {
        diagnostics?.sensorStatuses ?? []
    }

    private var readinessChecks: [ReadinessCheck] {
        guard let diagnostics else {
            return [
                ReadinessCheck(
                    title: "Receiving packets",
                    isPassing: false,
                    detail: "No telemetry yet."
                ),
            ]
        }

        let goodCount = diagnostics.fitReadiness.goodChannelCount
        let hsiGoodCount = diagnostics.fitReadiness.hsiGoodChannelCount
        let minimumGoodChannels = MuseArousalHeuristicConstants.minimumGoodChannels
        let rates = diagnostics.windowPassRates

        return [
            ReadinessCheck(
                title: "Receiving packets",
                isPassing: diagnostics.isReceivingData,
                detail: "\(packetAgeText(diagnostics.lastPacketAgeSeconds)) Rolling pass \(percentText(rates.receivingPackets)) in last 30 seconds."
            ),
            ReadinessCheck(
                title: "Headband-on coverage (>= 0.80)",
                isPassing: diagnostics.headbandOnCoverage >= 0.80,
                detail: String(
                    format: "Current %.2f. Rolling pass %@.",
                    diagnostics.headbandOnCoverage,
                    percentText(rates.headbandCoverage)
                )
            ),
            ReadinessCheck(
                title: "Quality-gate coverage (>= 0.60)",
                isPassing: diagnostics.qualityGateCoverage >= 0.60,
                detail: String(
                    format: "Current %.2f. Rolling pass %@.",
                    diagnostics.qualityGateCoverage,
                    percentText(rates.qualityGate)
                )
            ),
            ReadinessCheck(
                title: "Good EEG channels (>= \(minimumGoodChannels))",
                isPassing: goodCount >= minimumGoodChannels,
                detail: "Current \(goodCount). Rolling pass \(percentText(rates.eegGood3))."
            ),
            ReadinessCheck(
                title: "Good HSI channels (>= \(minimumGoodChannels))",
                isPassing: hsiGoodCount >= minimumGoodChannels,
                detail: "Current \(hsiGoodCount). Rolling pass \(percentText(rates.hsiGood3))."
            ),
            ReadinessCheck(
                title: "Composite readiness",
                isPassing: diagnostics.fitReadiness.isReady,
                detail: diagnostics.fitReadiness.primaryBlocker?.displayText ?? "Ready"
            ),
        ]
    }

    private var fitStatusText: String {
        guard let diagnostics else {
            return "Waiting for live Muse packet telemetry."
        }

        let streamStatus = diagnostics.isReceivingData
            ? "receiving live packets"
            : "not receiving recent packets"
        let confidenceText = String(format: "%.2f", diagnostics.signalConfidence)
        let awakeLikelihoodText = String(format: "%.2f", diagnostics.awakeLikelihood)
        let headbandCoverageText = String(format: "%.2f", diagnostics.headbandOnCoverage)
        let qualityCoverageText = String(format: "%.2f", diagnostics.qualityGateCoverage)
        let droppedTypeText = diagnostics.droppedPacketTypes.isEmpty
            ? "none"
            : diagnostics.droppedPacketTypes.map { "\($0.label): \($0.count)" }.joined(separator: ", ")
        let sdkWarningText = diagnostics.sdkWarningCounts.isEmpty
            ? "none"
            : diagnostics.sdkWarningCounts.map { "\($0.label): \($0.count)" }.joined(separator: ", ")

        return "Live status: \(streamStatus). Signal confidence \(confidenceText), awake likelihood (provisional) \(awakeLikelihoodText), headband-on coverage \(headbandCoverageText), quality-gate coverage \(qualityCoverageText). Dropped packet types: \(droppedTypeText). SDK timestamp warnings: \(sdkWarningText)."
    }

    private var fitPrimaryBlockerMessage: String {
        if let primaryBlockerText {
            return primaryBlockerText
        }
        if diagnostics == nil {
            return "waiting for live data."
        }
        if diagnostics?.fitReadiness.isReady == true {
            return "no blocker detected."
        }
        return "waiting for fit diagnostics."
    }

    private var fitPrimaryBlockerColor: Color {
        if diagnostics?.fitReadiness.isReady == true {
            return TelocareTheme.success
        }
        return TelocareTheme.coral
    }

    private func packetAgeText(_ ageSeconds: Double?) -> String {
        guard let ageSeconds else {
            return "No packet age available."
        }

        return String(format: "Last packet %.1fs ago.", ageSeconds)
    }

    private var diagnosisText: String {
        guard let diagnostics else {
            return "Waiting for enough telemetry to classify setup issues."
        }

        return "\(diagnostics.setupDiagnosis.displayText). \(diagnostics.setupDiagnosis.rationaleText)"
    }

    private var connectionHealthText: String {
        guard let diagnostics else {
            return "Connection health: waiting for packet telemetry."
        }

        let packetStatus = diagnostics.isReceivingData
            ? "Connection health: packets are arriving."
            : "Connection health: packet flow is unstable."
        let rollingPacketRate = percentText(diagnostics.windowPassRates.receivingPackets)
        let sdkWarnings = diagnostics.sdkWarningCounts.isEmpty
            ? "none"
            : diagnostics.sdkWarningCounts.map { "\($0.label) \($0.count)" }.joined(separator: ", ")

        return "\(packetStatus) Rolling receiving rate \(rollingPacketRate) over the last 30 seconds. SDK timestamp warnings: \(sdkWarnings)."
    }

    private var signalHealthText: String {
        guard let diagnostics else {
            return "Signal quality health: waiting for EEG fit telemetry."
        }

        let rates = diagnostics.windowPassRates
        let artifacts = diagnostics.artifactRates
        let latestHeadband = diagnostics.latestHeadbandOn.map { $0 ? "on" : "off" } ?? "unknown"
        let latestInputs = diagnostics.latestHasQualityInputs.map { $0 ? "present" : "missing" } ?? "unknown"

        return "Signal quality health: headband pass \(percentText(rates.headbandCoverage)), HSI-good>=3 pass \(percentText(rates.hsiGood3)), EEG-good>=3 pass \(percentText(rates.eegGood3)), quality-gate pass \(percentText(rates.qualityGate)) over the last 30 decision seconds. Blink rate \(percentText(artifacts.blinkTrueRate)), jaw-clench rate \(percentText(artifacts.jawClenchTrueRate)). Latest headband status \(latestHeadband); quality inputs \(latestInputs)."
    }

    private func percentText(_ value: Double) -> String {
        String(format: "%.0f%%", value * 100)
    }

    private var troubleshootingSummaryText: String {
        guard let diagnostics else {
            return "Plain-English summary: waiting for enough telemetry to explain the issue."
        }

        let rates = diagnostics.windowPassRates
        let hasHighArtifact = diagnostics.artifactRates.blinkTrueRate >= 0.50
            || diagnostics.artifactRates.jawClenchTrueRate >= 0.50

        let issueText: String
        if rates.eegGood3 < 0.10 && rates.hsiGood3 >= 0.40 {
            issueText = "Plain-English summary: the headband is connected and touching skin, but the EEG signal is too noisy to pass setup."
        } else if rates.receivingPackets < 0.90 {
            issueText = "Plain-English summary: packet flow is unstable, so quality checks cannot pass consistently."
        } else {
            issueText = "Plain-English summary: setup is not yet stable enough to pass all readiness checks."
        }

        let artifactText: String
        if hasHighArtifact {
            artifactText = "Blink or jaw movement is frequently detected, which can force is_good to fail."
        } else {
            artifactText = "Artifact rates are not dominant right now."
        }

        return "\(issueText) \(artifactText) \(failingSensorSummaryText)"
    }

    private var troubleshootingActionsText: String {
        guard let diagnostics else {
            return "Try this now: 1. Keep the band snug and clear hair from all contact points. 2. Hold still for 20 to 30 seconds. 3. Lightly dampen skin and sensors with clean water. 4. Re-check setup after 30 seconds."
        }

        let rates = diagnostics.windowPassRates
        let hasHighArtifact = diagnostics.artifactRates.blinkTrueRate >= 0.50
            || diagnostics.artifactRates.jawClenchTrueRate >= 0.50

        if rates.eegGood3 < 0.10 && rates.hsiGood3 >= 0.40 {
            let stillnessLine: String
            if hasHighArtifact {
                stillnessLine = "Relax your jaw, forehead, and eyes, and hold still for 20 to 30 seconds."
            } else {
                stillnessLine = "Hold still for 20 to 30 seconds after each adjustment."
            }

            return "Try this now: 1. Re-seat the band so forehead and ear sensors are flush, and clear hair from each contact point. 2. \(stillnessLine) 3. Lightly dampen forehead and behind-ear skin plus sensor pads with clean water. 4. Re-check setup after 30 seconds."
        }

        if rates.receivingPackets < 0.90 {
            return "Try this now: 1. Keep phone close to the headband and avoid switching apps during setup. 2. Reconnect the headband and retry calibration. 3. Reduce nearby Bluetooth interference if possible. 4. Once packets stabilize, repeat contact steps."
        }

        return "Try this now: 1. Keep the band snug and stable. 2. Hold still for 20 to 30 seconds. 3. Lightly dampen skin and sensor contact points. 4. Retry setup."
    }

    private var overnightTipsText: String {
        "Overnight tips: 1. Do a 2-minute fit check while lying in your sleep position before starting. 2. Keep the band snug enough that forehead and ear contacts do not shift when you move. 3. Lightly dampen contact points right before sleep; if water dries quickly, use a tiny amount of saline or EEG-safe conductive gel and clean sensors in the morning. 4. Keep hair and skin products off sensor sites."
    }

    private var failingSensorSummaryText: String {
        guard let diagnostics else {
            return "Current failing sensors: waiting for per-sensor telemetry."
        }

        let failingStatuses = diagnostics.sensorStatuses.filter { $0.passesIsGood == false }
        if failingStatuses.isEmpty {
            return "Current failing sensors: none."
        }

        let failingText = failingStatuses
            .map { "\($0.sensor.displayName) (\($0.sensor.locationText))" }
            .joined(separator: ", ")

        return "Current failing sensors: \(failingText)."
    }

    private func sensorRowText(for status: MuseSensorFitStatus) -> String {
        let isGoodText: String
        if let isGood = status.isGood {
            isGoodText = isGood ? "pass" : "fail"
        } else {
            isGoodText = "missing"
        }

        let hsiValueText: String
        if let hsiPrecision = status.hsiPrecision {
            hsiValueText = String(format: "%.2f", hsiPrecision)
        } else {
            hsiValueText = "missing"
        }

        let hsiStatusText = status.passesHsi ? "pass" : "fail"
        return "\(status.sensor.displayName) (\(status.sensor.locationText)): is_good \(isGoodText), hsi \(hsiValueText) (\(hsiStatusText))."
    }
}

private struct ReadinessCheck {
    let title: String
    let isPassing: Bool
    let detail: String

    var statusText: String {
        isPassing ? "PASS" : "FAIL"
    }
}
