//
//  CatchUpModalView.swift
//  Skywalker
//
//  Tinder-style catch-up flow for past interventions.
//

import SwiftUI
import UIKit

private enum SwipeDirection {
    case left
    case right
}

struct CatchUpModalView: View {
    var interventionService: InterventionService
    var healthKitService: HealthKitService
    let initialCards: [CatchUpCard]
    let currentSectionInfo: CurrentSectionInfo?

    @State private var deck: [CatchUpCard]
    @State private var stack: [CatchUpCard]
    @State private var doneCount: Int = 0
    @State private var skippedCount: Int = 0
    @State private var showCelebration: Bool = false
    @State private var celebrationDirection: SwipeDirection = .right
    @Environment(\.dismiss) private var dismiss
    private static let stackDepth = 4

    init(
        interventionService: InterventionService,
        healthKitService: HealthKitService,
        cards: [CatchUpCard],
        currentSectionInfo: CurrentSectionInfo?
    ) {
        self.interventionService = interventionService
        self.healthKitService = healthKitService
        self.initialCards = cards
        self.currentSectionInfo = currentSectionInfo
        _deck = State(initialValue: cards)
        _stack = State(initialValue: Array(cards.prefix(Self.stackDepth)))
    }

    var body: some View {
        NavigationView {
            GeometryReader { geometry in
                let cardHeight = geometry.size.height - 130 // Account for header and safe areas

                ZStack {
                    VStack(spacing: 0) {
                        header
                            .padding(.top, 12)

                        if deck.isEmpty {
                            summaryCard
                                .frame(height: cardHeight)
                                .padding(.horizontal, 20)
                                .padding(.top, 16)
                        } else {
                            cardStack
                                .frame(height: cardHeight)
                                .padding(.horizontal, 20)
                                .padding(.top, 16)
                        }

                        Spacer(minLength: 0)
                    }

                    // Celebration overlay
                    if showCelebration {
                        CelebrationOverlay(direction: celebrationDirection)
                    }
                }
            }
            .navigationTitle("Catch Up")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.large])
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Quick check-in")
                    .font(.headline)
                if !deck.isEmpty {
                    Text("Swipe right = done, left = skip")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            if !deck.isEmpty {
                let completed = initialCards.count - deck.count
                let currentIndex = min(completed + 1, initialCards.count)

                HStack(spacing: 4) {
                    Text("\(currentIndex)")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    Text("of \(initialCards.count)")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color(.secondarySystemBackground))
                .cornerRadius(20)
            }
        }
        .padding(.horizontal, 20)
    }

    private var summaryCard: some View {
        let total = doneCount + skippedCount
        let completionRate = total > 0 ? Double(doneCount) / Double(total) : 0

        return VStack(spacing: 32) {
            Spacer()

            // Celebration header based on completion rate
            VStack(spacing: 16) {
                ZStack {
                    Circle()
                        .fill(completionRate >= 0.7 ? Color.green.opacity(0.1) : Color.blue.opacity(0.1))
                        .frame(width: 120, height: 120)

                    if completionRate >= 0.9 {
                        Image(systemName: "star.fill")
                            .font(.system(size: 56))
                            .foregroundColor(.yellow)
                    } else if completionRate >= 0.7 {
                        Image(systemName: "hand.thumbsup.fill")
                            .font(.system(size: 50))
                            .foregroundColor(.green)
                    } else {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 50))
                            .foregroundColor(.blue)
                    }
                }

                VStack(spacing: 6) {
                    Text(completionMessage(rate: completionRate))
                        .font(.title)
                        .fontWeight(.bold)

                    Text(completionSubtitle(rate: completionRate))
                        .font(.body)
                        .foregroundColor(.secondary)
                }
            }

            // Stats breakdown
            HStack(spacing: 16) {
                VStack(spacing: 6) {
                    Text("\(doneCount)")
                        .font(.system(size: 36, weight: .bold, design: .rounded))
                        .foregroundColor(.green)
                    Text("Completed")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
                .background(Color(.secondarySystemBackground))
                .cornerRadius(16)

                VStack(spacing: 6) {
                    Text("\(skippedCount)")
                        .font(.system(size: 36, weight: .bold, design: .rounded))
                        .foregroundColor(.orange)
                    Text("Skipped")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
                .background(Color(.secondarySystemBackground))
                .cornerRadius(16)
            }

            // Next section info
            if let info = currentSectionInfo {
                HStack(spacing: 12) {
                    Image(systemName: info.section.icon)
                        .font(.title3)
                        .foregroundColor(info.section.color)
                        .frame(width: 36, height: 36)
                        .background(info.section.color.opacity(0.15))
                        .cornerRadius(10)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Up next: \(info.section.displayName)")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                        Text("\(remainingTimeString(info.remaining)) remaining")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Spacer()
                }
                .padding(14)
                .background(Color(.secondarySystemBackground))
                .cornerRadius(12)
            }

            Spacer()

            // Continue button
            Button(action: { dismiss() }) {
                Text("Continue")
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Color.blue)
                    .cornerRadius(14)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
        .cornerRadius(20)
        .shadow(color: Color.black.opacity(0.08), radius: 20, x: 0, y: 4)
    }

    private func completionMessage(rate: Double) -> String {
        if rate >= 0.9 { return "Amazing work!" }
        if rate >= 0.7 { return "Great job!" }
        if rate >= 0.5 { return "Good progress!" }
        return "All caught up"
    }

    private func completionSubtitle(rate: Double) -> String {
        if rate >= 0.9 { return "You're crushing it!" }
        if rate >= 0.7 { return "Keep up the momentum!" }
        if rate >= 0.5 { return "Every bit counts." }
        return "Ready for the next section."
    }

    private var cardStack: some View {
        let stackCards = stack

        return ZStack {
            ForEach(Array(stackCards.enumerated()), id: \.element.id) { index, card in
                let isTop = index == 0
                let depth = CGFloat(index)
                let yOffset = depth * 8  // Tighter stacking
                let scale = 1 - depth * 0.03  // Subtler scale
                let opacity = 1.0  // All cards at full opacity

                Group {
                    if isTop {
                        SwipeableCardView(
                            card: card,
                            count: bindingForTopCardCount(),
                            onSwipe: { direction in
                            handleSwipe(direction: direction, card: card)
                        },
                        healthKitService: healthKitService
                    )
                    } else {
                        CatchUpCardView(
                            card: card,
                            count: .constant(card.count),
                            healthKitService: healthKitService,
                            showHint: false
                        )
                    }
                }
                .scaleEffect(scale)
                .offset(y: yOffset)
                .opacity(opacity)
                .allowsHitTesting(isTop)
                .accessibilityHidden(!isTop)
                .zIndex(Double(stackCards.count - index))
            }
        }
    }

    private func handleSwipe(direction: SwipeDirection, card: CatchUpCard) {
        // Haptic feedback
        let generator = UIImpactFeedbackGenerator(style: direction == .right ? .medium : .light)
        generator.impactOccurred()

        // Track stats
        if direction == .right {
            doneCount += 1
        } else {
            skippedCount += 1
        }

        // Show celebration overlay
        celebrationDirection = direction
        showCelebration = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
            showCelebration = false
        }

        let status: InterventionDecisionStatus = direction == .right ? .done : .skipped
        let count = direction == .right ? (card.definition.trackingType == .counter ? max(card.count, 1) : nil) : nil

        interventionService.applyDecision(
            for: card.definition,
            on: card.day,
            status: status,
            count: count
        )

        // Advance deck without animation wrapper - deck changes animate via identity
        advanceDeck()
    }

    private func bindingForTopCardCount() -> Binding<Int> {
        Binding(
            get: { stack.first?.count ?? 1 },
            set: { newValue in
                updateTopCardCount(newValue)
            }
        )
    }

    private func updateTopCardCount(_ newValue: Int) {
        let safeValue = max(newValue, 0)
        guard !stack.isEmpty else { return }
        stack[0].count = safeValue
        if !deck.isEmpty {
            deck[0].count = safeValue
        }
    }

    private func advanceDeck() {
        if !stack.isEmpty {
            stack.removeFirst()
        }
        if !deck.isEmpty {
            deck.removeFirst()
        }

        if stack.count < Self.stackDepth, deck.count >= Self.stackDepth {
            stack.append(deck[Self.stackDepth - 1])
        }
    }

    private func remainingTimeString(_ remaining: TimeInterval) -> String {
        let hours = remaining / 3600
        let rounded = (hours * 2).rounded() / 2
        if rounded < 1 {
            return "0.5 hours"
        }
        if rounded == floor(rounded) {
            return "\(Int(rounded)) hours"
        }
        return String(format: "%.1f hours", rounded)
    }
}

private struct SwipeableCardView: View {
    let card: CatchUpCard
    @Binding var count: Int
    let onSwipe: (SwipeDirection) -> Void
    var healthKitService: HealthKitService

    @State private var offset: CGSize = .zero
    @State private var rotation: Double = 0
    @State private var glowColor: Color = .clear

    var body: some View {
        CatchUpCardView(
            card: card,
            count: $count,
            healthKitService: healthKitService
        )
        .overlay {
            RoundedRectangle(cornerRadius: 20)
                .stroke(glowColor, lineWidth: 4)
                .blur(radius: 4)
                .opacity(glowOpacity)
        }
        .offset(offset)
        .rotationEffect(.degrees(rotation))
        .gesture(
            DragGesture()
                .onChanged { value in
                    offset = value.translation
                    rotation = Double(value.translation.width / 20)

                    // Update glow based on direction
                    if value.translation.width > 40 {
                        glowColor = .green
                    } else if value.translation.width < -40 {
                        glowColor = .red
                    } else {
                        glowColor = .clear
                    }
                }
                .onEnded { value in
                    glowColor = .clear
                    if value.translation.width > 120 {
                        swipe(.right)
                    } else if value.translation.width < -120 {
                        swipe(.left)
                    } else {
                        withAnimation(.spring()) {
                            offset = .zero
                            rotation = 0
                        }
                    }
                }
        )
    }

    private var glowOpacity: Double {
        let threshold: CGFloat = 40
        let maxOpacity: Double = 0.8
        let distance = abs(offset.width)
        if distance < threshold { return 0 }
        return min((distance - threshold) / 80.0, maxOpacity)
    }

    private func swipe(_ direction: SwipeDirection) {
        let horizontal = direction == .right ? 600.0 : -600.0
        withAnimation(.easeIn(duration: 0.25)) {
            offset = CGSize(width: horizontal, height: 0)
            rotation = direction == .right ? 15 : -15
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.28) {
            offset = .zero
            rotation = 0
            onSwipe(direction)
        }
    }
}

private struct CatchUpCardView: View {
    let card: CatchUpCard
    @Binding var count: Int
    var healthKitService: HealthKitService
    var showHint: Bool = true

    @Environment(\.catalogDataService) private var catalogDataService
    @State private var showingDetail = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // MARK: - Header
            VStack(alignment: .leading, spacing: 14) {
                // Section label
                HStack {
                    Image(systemName: card.section.icon)
                        .font(.caption)
                        .foregroundColor(card.section.color)
                    Text(card.sectionLabel)
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(.secondary)
                    Spacer()
                }

                // Emoji and name
                HStack(spacing: 14) {
                    Text(card.definition.emoji)
                        .font(.system(size: 44))

                    VStack(alignment: .leading, spacing: 4) {
                        Text(card.definition.name)
                            .font(.title3)
                            .fontWeight(.bold)
                            .lineLimit(2)

                        Text(card.definition.description)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .lineLimit(2)
                    }

                    Spacer()
                }
            }
            .padding(20)

            Divider()
                .padding(.horizontal, 20)

            // MARK: - Content (compact, with "See details" button)
            VStack(alignment: .leading, spacing: 16) {
                // Evidence summary (always truncated on card)
                if let summary = card.definition.evidenceSummary, !summary.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(summary)
                            .font(.subheadline)
                            .foregroundColor(.primary)
                            .lineLimit(3)

                        // Citations preview
                        let citations = catalogDataService.citations(forIds: card.definition.citationIds)
                        if !citations.isEmpty {
                            HStack(spacing: 6) {
                                ForEach(citations.prefix(3)) { citation in
                                    CitationBadge(citation: citation)
                                }
                                if citations.count > 3 {
                                    Text("+\(citations.count - 3)")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                    }
                }

                // "See details" button - opens sheet
                if hasDetailContent {
                    Button(action: { showingDetail = true }) {
                        HStack(spacing: 6) {
                            Image(systemName: "doc.text.magnifyingglass")
                                .font(.caption)
                            Text("See full details")
                                .font(.subheadline)
                                .fontWeight(.medium)
                        }
                        .foregroundColor(.blue)
                        .padding(.vertical, 10)
                        .padding(.horizontal, 16)
                        .background(Color.blue.opacity(0.1))
                        .cornerRadius(8)
                    }
                    .buttonStyle(PlainButtonStyle())
                }

                // Impact row (compact)
                compactImpactRow

                // Counter stepper (if applicable)
                if card.definition.trackingType == .counter {
                    HStack {
                        Text("How many?")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        Spacer()
                        CounterStepper(value: $count)
                    }
                }

                // Health hint (if applicable)
                if showHint, let hintType = card.healthHintType {
                    HealthHintView(
                        hintType: hintType,
                        interval: card.interval,
                        healthKitService: healthKitService
                    )
                }
            }
            .padding(20)

            Spacer(minLength: 0)

            // MARK: - Footer (swipe hints)
            VStack(spacing: 0) {
                Divider()
                    .padding(.horizontal, 20)

                HStack {
                    HStack(spacing: 8) {
                        Circle()
                            .fill(Color.red.opacity(0.15))
                            .frame(width: 32, height: 32)
                            .overlay(
                                Image(systemName: "xmark")
                                    .font(.caption.bold())
                                    .foregroundColor(.red)
                            )
                        Text("Skip")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    HStack(spacing: 8) {
                        Text("Done")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        Circle()
                            .fill(Color.green.opacity(0.15))
                            .frame(width: 32, height: 32)
                            .overlay(
                                Image(systemName: "checkmark")
                                    .font(.caption.bold())
                                    .foregroundColor(.green)
                            )
                    }
                }
                .padding(20)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
        .cornerRadius(20)
        .shadow(color: Color.black.opacity(0.08), radius: 20, x: 0, y: 4)
        .sheet(isPresented: $showingDetail) {
            InterventionDetailSheet(
                definition: card.definition,
                catalogDataService: catalogDataService
            )
        }
    }

    // MARK: - Content Check

    private var hasDetailContent: Bool {
        let hasDetailedDescription = card.definition.detailedDescription != nil &&
            card.definition.detailedDescription != card.definition.description &&
            !(card.definition.detailedDescription?.isEmpty ?? true)
        let hasEvidence = !(card.definition.evidenceSummary?.isEmpty ?? true)
        let hasCitations = !card.definition.citationIds.isEmpty
        return hasDetailedDescription || hasEvidence || hasCitations
    }

    // MARK: - Compact Impact Row

    @ViewBuilder
    private var compactImpactRow: some View {
        HStack(spacing: 16) {
            // ROI badge
            if let roi = card.definition.roiTier {
                HStack(spacing: 6) {
                    Text(roi)
                        .font(.caption2)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                        .frame(width: 20, height: 20)
                        .background(roiColor(roi))
                        .cornerRadius(4)
                    Text(roiDescription(roi))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            // Evidence tier
            HStack(spacing: 4) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.caption2)
                    .foregroundColor(tierColor)
                Text(card.definition.tier.displayName)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            // Cost (if free, show it)
            if let cost = card.definition.costRange, cost == "$0" {
                Text("Free")
                    .font(.caption)
                    .foregroundColor(.green)
            }
        }
        .padding(12)
        .background(Color(.secondarySystemBackground))
        .cornerRadius(10)
    }

    // MARK: - Helper Functions

    private var tierColor: Color {
        switch card.definition.tier {
        case .strong: return .green
        case .moderate: return .blue
        case .lower: return .orange
        }
    }

    private func roiColor(_ roi: String) -> Color {
        switch roi {
        case "A": return .green
        case "B": return Color(red: 0.4, green: 0.7, blue: 0.2)
        case "C": return .blue
        case "D": return .orange
        case "E": return .red
        default: return .gray
        }
    }

    private func roiDescription(_ roi: String) -> String {
        switch roi {
        case "A": return "Very High"
        case "B": return "High"
        case "C": return "Moderate"
        case "D": return "Lower"
        case "E": return "Minimal"
        default: return "Unknown"
        }
    }
}

// MARK: - Intervention Detail Sheet

private struct InterventionDetailSheet: View {
    let definition: InterventionDefinition
    let catalogDataService: CatalogDataService
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // Header
                    HStack(spacing: 16) {
                        Text(definition.emoji)
                            .font(.system(size: 56))

                        VStack(alignment: .leading, spacing: 6) {
                            Text(definition.name)
                                .font(.title2)
                                .fontWeight(.bold)

                            Text(definition.description)
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.bottom, 8)

                    // Detailed description
                    if let detailed = definition.detailedDescription,
                       !detailed.isEmpty,
                       detailed != definition.description {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("About")
                                .font(.headline)
                            Text(detailed)
                                .font(.body)
                                .foregroundColor(.primary)
                        }
                    }

                    // Evidence section
                    if let summary = definition.evidenceSummary, !summary.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Image(systemName: "checkmark.seal.fill")
                                    .foregroundColor(tierColor)
                                Text("Evidence (\(definition.tier.displayName))")
                                    .font(.headline)
                            }

                            Text(summary)
                                .font(.body)
                                .foregroundColor(.primary)
                        }
                        .padding(16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(.secondarySystemBackground))
                        .cornerRadius(12)
                    }

                    // Citations
                    let citations = catalogDataService.citations(forIds: definition.citationIds)
                    if !citations.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Sources")
                                .font(.headline)

                            CitationList(citations: citations, title: "")
                        }
                    }

                    // Implementation details
                    if definition.costRange != nil || definition.easeScore != nil {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Implementation")
                                .font(.headline)

                            HStack(spacing: 24) {
                                if let cost = definition.costRange {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("Cost")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                        Text(cost)
                                            .font(.body)
                                            .fontWeight(.medium)
                                    }
                                }

                                if let ease = definition.easeScore {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("Ease of Implementation")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                        HStack(spacing: 4) {
                                            Text("\(ease)/10")
                                                .font(.body)
                                                .fontWeight(.medium)
                                            Text(easeLabel(ease))
                                                .font(.caption)
                                                .foregroundColor(easeColor(ease))
                                        }
                                    }
                                }

                                Spacer()
                            }
                        }
                        .padding(16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(.secondarySystemBackground))
                        .cornerRadius(12)
                    }

                    // ROI info
                    if let roi = definition.roiTier {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Return on Investment")
                                .font(.headline)

                            HStack(spacing: 12) {
                                Text(roi)
                                    .font(.title2)
                                    .fontWeight(.bold)
                                    .foregroundColor(.white)
                                    .frame(width: 40, height: 40)
                                    .background(roiColor(roi))
                                    .cornerRadius(8)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(roiTitle(roi))
                                        .font(.subheadline)
                                        .fontWeight(.semibold)
                                    Text(roiExplanation(roi))
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                    }
                }
                .padding(24)
            }
            .navigationTitle("Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private var tierColor: Color {
        switch definition.tier {
        case .strong: return .green
        case .moderate: return .blue
        case .lower: return .orange
        }
    }

    private func roiColor(_ roi: String) -> Color {
        switch roi {
        case "A": return .green
        case "B": return Color(red: 0.4, green: 0.7, blue: 0.2)
        case "C": return .blue
        case "D": return .orange
        case "E": return .red
        default: return .gray
        }
    }

    private func roiTitle(_ roi: String) -> String {
        switch roi {
        case "A": return "Excellent ROI"
        case "B": return "Very Good ROI"
        case "C": return "Good ROI"
        case "D": return "Moderate ROI"
        case "E": return "Lower ROI"
        default: return "Unknown"
        }
    }

    private func roiExplanation(_ roi: String) -> String {
        switch roi {
        case "A": return "High impact, low effort - prioritize this"
        case "B": return "Strong benefits relative to effort required"
        case "C": return "Worthwhile investment of time and energy"
        case "D": return "Benefits may take longer to realize"
        case "E": return "Consider if other options aren't feasible"
        default: return ""
        }
    }

    private func easeColor(_ score: Int) -> Color {
        if score >= 8 { return .green }
        if score >= 5 { return .blue }
        return .orange
    }

    private func easeLabel(_ score: Int) -> String {
        if score >= 8 { return "Easy" }
        if score >= 5 { return "Moderate" }
        return "Challenging"
    }
}


private struct CounterStepper: View {
    @Binding var value: Int

    var body: some View {
        HStack(spacing: 10) {
            Button(action: { value = max(value - 1, 0) }) {
                Image(systemName: "minus.circle.fill")
                    .foregroundColor(.secondary)
                    .font(.title3)
            }

            Text("\(value)")
                .font(.headline)
                .frame(minWidth: 30)

            Button(action: { value += 1 }) {
                Image(systemName: "plus.circle.fill")
                    .foregroundColor(.blue)
                    .font(.title3)
            }
        }
    }
}

private enum HealthHintState {
    case idle
    case loading
    case available(String)
    case empty(String)
    case notAuthorized
}

private struct HealthHintView: View {
    let hintType: HealthHintType
    let interval: DateInterval
    var healthKitService: HealthKitService

    @State private var state: HealthHintState = .idle
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Apple Health")
                .font(.caption)
                .foregroundColor(.secondary)

            switch state {
            case .idle, .loading:
                ProgressView()
                    .scaleEffect(0.8)
            case .available(let text):
                Text(text)
                    .font(.subheadline)
                    .foregroundColor(.primary)
            case .empty(let text):
                Text(text)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            case .notAuthorized:
                Button("Connect to Apple Health") {
                    Task {
                        _ = await healthKitService.requestAuthorization(for: hintType)
                        await loadHint()
                    }
                }
                .font(.subheadline)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.06))
        .cornerRadius(12)
        .task(id: "\(hintType.rawValue)-\(interval.start.timeIntervalSinceReferenceDate)") {
            await loadHint()
        }
        .onChange(of: scenePhase) { newPhase in
            if newPhase == .active {
                Task { await loadHint() }
            }
        }
    }

    private func loadHint() async {
        guard healthKitService.isAuthorized(for: hintType) else {
            state = .notAuthorized
            return
        }

        state = .loading

        do {
            switch hintType {
            case .exercise:
                let summary = try await healthKitService.fetchWorkoutSummary(in: interval)
                if summary.count == 0 && summary.minutes == 0 {
                    state = .empty("No workouts logged in this window.")
                } else {
                    state = .available("\(summary.count) workout(s) • \(Int(summary.minutes.rounded())) min")
                }
            case .water:
                let liters = try await healthKitService.fetchWaterLiters(in: interval)
                if liters == 0 {
                    state = .empty("No water logged in this window.")
                } else {
                    state = .available(String(format: "%.1f L logged", liters))
                }
            case .mindfulness:
                let minutes = try await healthKitService.fetchMindfulMinutes(in: interval)
                if minutes == 0 {
                    state = .empty("No mindful sessions logged in this window.")
                } else {
                    state = .available("\(Int(minutes.rounded())) min mindful sessions")
                }
            }
        } catch let error as HealthKitService.HealthKitError {
            if case .notAuthorized = error {
                state = .notAuthorized
            } else {
                state = .empty("No Apple Health data available.")
            }
        } catch {
            state = .empty("No Apple Health data available.")
        }
    }
}

// MARK: - Celebration Overlay

private struct CelebrationOverlay: View {
    let direction: SwipeDirection
    @State private var scale: CGFloat = 0.5
    @State private var opacity: Double = 1.0
    @State private var particleOffsets: [(x: CGFloat, y: CGFloat)] = Array(repeating: (0, 0), count: 8)
    @State private var particleScales: [CGFloat] = Array(repeating: 0.5, count: 8)

    var body: some View {
        ZStack {
            if direction == .right {
                // Success celebration
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 80))
                    .foregroundColor(.green)
                    .scaleEffect(scale)
                    .opacity(opacity)

                // Burst particles
                ForEach(0..<8, id: \.self) { i in
                    Image(systemName: "sparkle")
                        .font(.system(size: 14))
                        .foregroundColor(.green.opacity(0.8))
                        .offset(x: particleOffsets[i].x, y: particleOffsets[i].y)
                        .scaleEffect(particleScales[i])
                        .opacity(opacity)
                }
            }
            // Skip: No overlay - just let the card animate out
        }
        .onAppear {
            guard direction == .right else { return }

            // Animate in
            withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                scale = 1.2
            }

            // Animate particles outward
            withAnimation(.easeOut(duration: 0.4)) {
                for i in 0..<8 {
                    let angle = Double(i) * (360.0 / 8.0) * .pi / 180
                    particleOffsets[i] = (cos(angle) * 60, sin(angle) * 60)
                    particleScales[i] = 1.0
                }
            }

            // Settle
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                withAnimation(.easeOut(duration: 0.2)) {
                    scale = 1.0
                }
            }

            // Fade out
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                withAnimation(.easeOut(duration: 0.2)) {
                    opacity = 0
                }
            }
        }
    }
}

#Preview {
    CatchUpModalView(
        interventionService: InterventionService(),
        healthKitService: HealthKitService(),
        cards: [],
        currentSectionInfo: nil
    )
}
