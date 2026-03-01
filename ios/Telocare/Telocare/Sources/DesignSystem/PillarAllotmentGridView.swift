import SwiftUI

struct KitchenGardenGridSection: View {
    let snapshots: [KitchenGardenSnapshot]
    let selectedPillarIDs: Set<String>
    let isAllSelected: Bool
    let onTapPillar: (HealthPillar) -> Void
    let onShowAll: () -> Void
    let accessibilityIdentifier: String
    let cardAccessibilityIdentifier: (String) -> String

    var body: some View {
        PillarAllotmentGridSection(
            title: "Kitchen Garden",
            subtitle: "What you can control",
            snapshots: snapshots,
            selectedPillarIDs: selectedPillarIDs,
            isAllSelected: isAllSelected,
            onShowAll: onShowAll,
            accessibilityIdentifier: accessibilityIdentifier,
            cardAccessibilityIdentifier: cardAccessibilityIdentifier
        ) { snapshot in
            KitchenGardenCardView(
                snapshot: snapshot,
                selectedPillarIDs: selectedPillarIDs,
                isAllSelected: isAllSelected,
                onTapPillar: onTapPillar
            )
        }
    }
}

struct HarvestTableGridSection: View {
    let snapshots: [HarvestTableSnapshot]
    let selectedPillarIDs: Set<String>
    let isAllSelected: Bool
    let onTapPillar: (HealthPillar) -> Void
    let onShowAll: () -> Void
    let accessibilityIdentifier: String
    let cardAccessibilityIdentifier: (String) -> String

    var body: some View {
        PillarAllotmentGridSection(
            title: "Harvest Table",
            subtitle: "What you measure",
            snapshots: snapshots,
            selectedPillarIDs: selectedPillarIDs,
            isAllSelected: isAllSelected,
            onShowAll: onShowAll,
            accessibilityIdentifier: accessibilityIdentifier,
            cardAccessibilityIdentifier: cardAccessibilityIdentifier
        ) { snapshot in
            HarvestTableCardView(
                snapshot: snapshot,
                selectedPillarIDs: selectedPillarIDs,
                isAllSelected: isAllSelected,
                onTapPillar: onTapPillar
            )
        }
    }
}

private struct PillarAllotmentGridSection<Snapshot: Identifiable, Card: View>: View where Snapshot.ID == String {
    let title: String
    let subtitle: String
    let snapshots: [Snapshot]
    let selectedPillarIDs: Set<String>
    let isAllSelected: Bool
    let onShowAll: () -> Void
    let accessibilityIdentifier: String
    let cardAccessibilityIdentifier: (String) -> String
    let card: (Snapshot) -> Card

    private var visibleSnapshots: [Snapshot] {
        if isAllSelected {
            return snapshots
        }
        if selectedPillarIDs.isEmpty {
            return []
        }
        return snapshots.filter { selectedPillarIDs.contains($0.id) }
    }

    private var columnCount: Int {
        let count = visibleSnapshots.count
        if count <= 1 {
            return 1
        }
        if count <= 4 {
            return 2
        }
        return 3
    }

    private var columns: [GridItem] {
        Array(
            repeating: GridItem(.flexible(minimum: 0), spacing: TelocareTheme.Spacing.sm),
            count: columnCount
        )
    }

    private var focusedCardMaxWidth: CGFloat {
        540
    }

    var body: some View {
        VStack(alignment: .leading, spacing: TelocareTheme.Spacing.sm) {
            header

            LazyVGrid(columns: columns, spacing: TelocareTheme.Spacing.sm) {
                ForEach(visibleSnapshots) { snapshot in
                    if visibleSnapshots.count == 1 {
                        HStack {
                            Spacer(minLength: 0)
                            PillarAllotmentCardContainer {
                                card(snapshot)
                            }
                            .frame(maxWidth: focusedCardMaxWidth)
                            .accessibilityIdentifier(cardAccessibilityIdentifier(snapshot.id))
                            Spacer(minLength: 0)
                        }
                        .gridCellColumns(columnCount)
                    } else {
                        PillarAllotmentCardContainer {
                            card(snapshot)
                        }
                        .accessibilityIdentifier(cardAccessibilityIdentifier(snapshot.id))
                    }
                }
            }
        }
        .accessibilityIdentifier(accessibilityIdentifier)
    }

    @ViewBuilder
    private var header: some View {
        HStack(alignment: .top, spacing: TelocareTheme.Spacing.sm) {
            WarmSectionHeader(
                title: title,
                subtitle: subtitle
            )
            Spacer()
            if !isAllSelected {
                Button("Show all") {
                    onShowAll()
                }
                .buttonStyle(.bordered)
            }
        }
    }
}

private struct PillarAllotmentCardContainer<Content: View>: View {
    let content: Content
    private let cardAspectRatio: CGFloat = 1

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        Color.clear
            .aspectRatio(cardAspectRatio, contentMode: .fit)
            .overlay {
                content
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .clipped()
    }
}

private struct KitchenGardenCardView: View {
    let snapshot: KitchenGardenSnapshot
    let selectedPillarIDs: Set<String>
    let isAllSelected: Bool
    let onTapPillar: (HealthPillar) -> Void

    private var palette: PillarAllotmentPalette {
        PillarAllotmentPalette.resolve(for: snapshot.pillar.id.id)
    }

    var body: some View {
        let isSelected = selectedPillarIDs.contains(snapshot.id)
        let isDimmed = !isAllSelected && !selectedPillarIDs.isEmpty && !isSelected

        Button {
            onTapPillar(snapshot.pillar.id)
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                ZStack(alignment: .topLeading) {
                    GardenBedIllustration(
                        palette: palette,
                        stage: snapshot.effortStage
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                    LinearGradient(
                        colors: [.black.opacity(0.38), .clear],
                        startPoint: .top,
                        endPoint: .center
                    )
                    .clipShape(
                        RoundedRectangle(
                            cornerRadius: TelocareTheme.CornerRadius.medium,
                            style: .continuous
                        )
                    )

                    Text(snapshot.pillar.title)
                        .font(TelocareTheme.Typography.small.weight(.bold))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                        .padding(.horizontal, 8)
                        .padding(.top, 7)
                }

                HStack(spacing: 4) {
                    Text(kitchenCaptionText)
                        .font(TelocareTheme.Typography.small)
                        .foregroundStyle(TelocareTheme.warmGray)
                        .lineLimit(1)
                    Spacer(minLength: 4)
                }
                .frame(height: 16)
            }
            .padding(6)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(TelocareTheme.cream)
            .clipShape(
                RoundedRectangle(
                    cornerRadius: TelocareTheme.CornerRadius.medium,
                    style: .continuous
                )
            )
            .overlay(
                RoundedRectangle(
                    cornerRadius: TelocareTheme.CornerRadius.medium,
                    style: .continuous
                )
                .stroke(isSelected ? TelocareTheme.coral : palette.foliage.opacity(0.28), lineWidth: isSelected ? 2 : 1)
            )
            .clipped()
        }
        .buttonStyle(.plain)
        .opacity(isDimmed ? 0.35 : 1)
        .scaleEffect(isDimmed ? 0.97 : 1)
        .animation(.easeInOut(duration: 0.2), value: selectedPillarIDs)
        .animation(.easeInOut(duration: 0.2), value: isAllSelected)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(snapshot.pillar.title) kitchen garden")
        .accessibilityValue(accessibilityValue)
        .accessibilityHint(accessibilityHint(isSelected: isSelected))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var accessibilityValue: String {
        let percent = Int((snapshot.effortFraction * 100).rounded())
        let stageDescription = GardenStageDescription.describe(stage: snapshot.effortStage)
        if snapshot.mappedHabitCount == 0 {
            return "No habits mapped to this pillar. \(stageDescription)."
        }

        if snapshot.activeHabitCount == 0 {
            return "\(snapshot.mappedHabitCount) habits mapped, none active today. \(stageDescription)."
        }

        return "\(percent) percent effort, \(snapshot.completedHabitCount) of \(snapshot.activeHabitCount) active habits complete, \(stageDescription)."
    }

    private var kitchenCaptionText: String {
        return GardenStageDescription.describe(stage: snapshot.effortStage).capitalized
    }

    private func accessibilityHint(isSelected: Bool) -> String {
        if isSelected && !isAllSelected && selectedPillarIDs.count == 1 {
            return "Double tap to show all pillars."
        }
        return "Double tap to focus this pillar."
    }
}

private struct HarvestTableCardView: View {
    let snapshot: HarvestTableSnapshot
    let selectedPillarIDs: Set<String>
    let isAllSelected: Bool
    let onTapPillar: (HealthPillar) -> Void

    private var palette: PillarAllotmentPalette {
        PillarAllotmentPalette.resolve(for: snapshot.pillar.id.id)
    }

    var body: some View {
        let isSelected = selectedPillarIDs.contains(snapshot.id)
        let isDimmed = !isAllSelected && !selectedPillarIDs.isEmpty && !isSelected

        Button {
            onTapPillar(snapshot.pillar.id)
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                ZStack(alignment: .topLeading) {
                    HarvestTableIllustration(
                        palette: palette,
                        foodStage: snapshot.foodStage,
                        flowerStage: snapshot.effortStage
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                    LinearGradient(
                        colors: [.black.opacity(0.35), .clear],
                        startPoint: .top,
                        endPoint: .center
                    )
                    .clipShape(
                        RoundedRectangle(
                            cornerRadius: TelocareTheme.CornerRadius.medium,
                            style: .continuous
                        )
                    )

                    Text(snapshot.pillar.title)
                        .font(TelocareTheme.Typography.small.weight(.bold))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                        .padding(.horizontal, 8)
                        .padding(.top, 7)
                }

                HStack(spacing: 4) {
                    Text(harvestCaptionText)
                        .font(TelocareTheme.Typography.small)
                        .foregroundStyle(TelocareTheme.charcoal)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(height: 16)
            }
            .padding(6)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(TelocareTheme.cream)
            .clipShape(
                RoundedRectangle(
                    cornerRadius: TelocareTheme.CornerRadius.medium,
                    style: .continuous
                )
            )
            .overlay(
                RoundedRectangle(
                    cornerRadius: TelocareTheme.CornerRadius.medium,
                    style: .continuous
                )
                .stroke(isSelected ? TelocareTheme.coral : palette.harvest.opacity(0.28), lineWidth: isSelected ? 2 : 1)
            )
            .clipped()
        }
        .buttonStyle(.plain)
        .opacity(isDimmed ? 0.35 : 1)
        .scaleEffect(isDimmed ? 0.97 : 1)
        .animation(.easeInOut(duration: 0.2), value: selectedPillarIDs)
        .animation(.easeInOut(duration: 0.2), value: isAllSelected)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(snapshot.pillar.title) harvest table")
        .accessibilityValue(accessibilityValue)
        .accessibilityHint(accessibilityHint(isSelected: isSelected))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var accessibilityValue: String {
        let flowerDescription = GardenStageDescription.describe(stage: snapshot.effortStage)
        let foodDescription = HarvestFoodDescription.describe(stage: snapshot.foodStage)
        guard let outcomeFraction = snapshot.rollingOutcomeFraction else {
            return "No 7 day outcome check-ins yet, \(foodDescription). Effort \(Int((snapshot.effortFraction * 100).rounded())) percent, \(flowerDescription)."
        }

        let outcomePercent = Int((outcomeFraction * 100).rounded())
        return "\(snapshot.outcomeSampleCount) recent check-ins, food \(outcomePercent) percent, \(foodDescription). Effort flowers \(Int((snapshot.effortFraction * 100).rounded())) percent, \(flowerDescription)."
    }

    private var harvestCaptionText: String {
        HarvestFoodDescription.describe(stage: snapshot.foodStage).capitalized
    }

    private func accessibilityHint(isSelected: Bool) -> String {
        if isSelected && !isAllSelected && selectedPillarIDs.count == 1 {
            return "Double tap to show all pillars."
        }
        return "Double tap to focus this pillar."
    }
}

private struct GardenBedIllustration: View {
    let palette: PillarAllotmentPalette
    let stage: Int

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isSwaying = false

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: TelocareTheme.CornerRadius.medium, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [palette.soil, palette.soil.opacity(0.85)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            VStack(spacing: 5) {
                ForEach(0..<3, id: \.self) { row in
                    HStack(spacing: 5) {
                        ForEach(0..<4, id: \.self) { column in
                            GardenPlantCell(
                                stage: stage,
                                palette: palette,
                                slotIndex: row * 4 + column
                            )
                        }
                    }
                }
            }
            .padding(10)
            .rotationEffect(.degrees(isSwaying ? 1.6 : -1.6))

            if stage == 10 {
                Image(systemName: "sparkles")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(palette.blossom.opacity(0.88))
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: TelocareTheme.CornerRadius.medium, style: .continuous)
                .stroke(palette.foliage.opacity(0.22), lineWidth: 1)
        )
        .onAppear {
            guard !reduceMotion else {
                return
            }
            isSwaying = true
        }
        .animation(
            reduceMotion ? nil : .easeInOut(duration: 2.1).repeatForever(autoreverses: true),
            value: isSwaying
        )
    }
}

private struct GardenPlantCell: View {
    let stage: Int
    let palette: PillarAllotmentPalette
    let slotIndex: Int

    private var foliageSlots: Int {
        min(12, max(0, (stage - 1) * 2))
    }

    private var flowerSlots: Int {
        min(12, max(0, stage - 4))
    }

    var body: some View {
        if stage == 1 {
            seedView
        } else if slotIndex < foliageSlots {
            foliageView
        } else {
            Color.clear
                .frame(width: 16, height: 16)
        }
    }

    private var seedView: some View {
        Circle()
            .fill(slotIndex < 3 ? palette.seed : Color.clear)
            .frame(width: 4, height: 4)
            .frame(width: 16, height: 16)
    }

    private var foliageView: some View {
        ZStack(alignment: .top) {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [palette.foliage, palette.foliage.opacity(0.65)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: foliageSize, height: foliageSize)

            if slotIndex < flowerSlots {
                Circle()
                    .fill(palette.blossom)
                    .frame(width: blossomSize, height: blossomSize)
                    .offset(y: -foliageSize * 0.35)
            }
        }
        .frame(width: 16, height: 16)
    }

    private var foliageSize: CGFloat {
        CGFloat(min(14, max(6, stage + 3)))
    }

    private var blossomSize: CGFloat {
        CGFloat(min(8, max(3, stage - 2)))
    }
}

private struct HarvestTableIllustration: View {
    let palette: PillarAllotmentPalette
    let foodStage: Int
    let flowerStage: Int

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isBobbing = false

    private var foodCount: Int {
        PillarAllotmentMath.count(for: foodStage, maxCount: 8)
    }

    private var flowerCount: Int {
        PillarAllotmentMath.count(for: flowerStage, maxCount: 4)
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: TelocareTheme.CornerRadius.medium, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [palette.wood, palette.wood.opacity(0.75)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            VStack(spacing: 6) {
                HStack(spacing: 6) {
                    ForEach(0..<4, id: \.self) { index in
                        HarvestFoodCell(
                            isVisible: index < foodCount,
                            palette: palette,
                            slotIndex: index
                        )
                    }
                }

                HStack(spacing: 6) {
                    ForEach(4..<8, id: \.self) { index in
                        HarvestFoodCell(
                            isVisible: index < foodCount,
                            palette: palette,
                            slotIndex: index
                        )
                    }
                }

                HStack(spacing: 8) {
                    ForEach(0..<4, id: \.self) { index in
                        HarvestFlowerCell(
                            isVisible: index < flowerCount,
                            palette: palette
                        )
                    }
                }
                .padding(.top, 2)
                .offset(y: isBobbing ? -1.2 : 1.2)
            }
            .padding(10)
        }
        .overlay(
            RoundedRectangle(cornerRadius: TelocareTheme.CornerRadius.medium, style: .continuous)
                .stroke(palette.harvest.opacity(0.2), lineWidth: 1)
        )
        .onAppear {
            guard !reduceMotion else {
                return
            }
            isBobbing = true
        }
        .animation(
            reduceMotion ? nil : .easeInOut(duration: 2.0).repeatForever(autoreverses: true),
            value: isBobbing
        )
    }
}

private struct HarvestFoodCell: View {
    let isVisible: Bool
    let palette: PillarAllotmentPalette
    let slotIndex: Int

    var body: some View {
        Group {
            if isVisible {
                ZStack {
                    if slotIndex.isMultiple(of: 3) {
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [palette.harvest, palette.harvest.opacity(0.78)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    } else {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [palette.harvest, palette.harvest.opacity(0.78)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    }

                    Capsule()
                        .fill(palette.foliage.opacity(0.65))
                        .frame(width: 5, height: 2)
                        .offset(y: -4)
                }
                .rotationEffect(.degrees(slotIndex.isMultiple(of: 2) ? -8 : 8))
            } else {
                Circle()
                    .fill(Color.white.opacity(0.09))
            }
        }
        .frame(width: 10, height: 10)
    }
}

private struct HarvestFlowerCell: View {
    let isVisible: Bool
    let palette: PillarAllotmentPalette

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(Color.white.opacity(0.16))
                .frame(width: 8, height: 4)
                .offset(y: 4)

            if isVisible {
                ZStack {
                    Circle().fill(palette.blossom.opacity(0.85)).frame(width: 4, height: 4).offset(x: -3)
                    Circle().fill(palette.blossom.opacity(0.85)).frame(width: 4, height: 4).offset(x: 3)
                    Circle().fill(palette.blossom).frame(width: 4, height: 4).offset(y: -3)
                    Circle().fill(palette.foliage.opacity(0.75)).frame(width: 3, height: 3)
                }
            }
        }
        .frame(width: 12, height: 12)
    }
}

private struct PillarAllotmentPalette {
    let foliage: Color
    let blossom: Color
    let harvest: Color
    let soil: Color
    let wood: Color
    let seed: Color

    static func resolve(for pillarID: String) -> PillarAllotmentPalette {
        let hash = stableHash(of: pillarID.lowercased())
        let hue = Double(hash % 360) / 360.0
        let blossomHue = (hue + 0.11).truncatingRemainder(dividingBy: 1)
        let harvestHue = (hue + 0.05).truncatingRemainder(dividingBy: 1)
        let soilHue = (hue + 0.08).truncatingRemainder(dividingBy: 1)
        let woodHue = (hue + 0.03).truncatingRemainder(dividingBy: 1)
        let foliage = Color(hue: hue, saturation: 0.72, brightness: 0.58)
        let blossom = Color(hue: blossomHue, saturation: 0.50, brightness: 0.91)
        let harvest = Color(hue: harvestHue, saturation: 0.78, brightness: 0.74)
        return PillarAllotmentPalette(
            foliage: foliage,
            blossom: blossom,
            harvest: harvest,
            soil: Color(hue: soilHue, saturation: 0.44, brightness: 0.31),
            wood: Color(hue: woodHue, saturation: 0.37, brightness: 0.47),
            seed: Color(hue: soilHue, saturation: 0.40, brightness: 0.38)
        )
    }

    private static func stableHash(of text: String) -> UInt64 {
        var hash: UInt64 = 1469598103934665603
        for scalar in text.unicodeScalars {
            hash ^= UInt64(scalar.value)
            hash = hash &* 1099511628211
        }
        return hash
    }
}

private enum PillarAllotmentMath {
    static func count(for stage: Int, maxCount: Int) -> Int {
        let clampedStage = min(10, max(1, stage))
        let fraction = Double(clampedStage - 1) / 9.0
        return min(maxCount, max(0, Int((Double(maxCount) * fraction).rounded())))
    }
}

private enum GardenStageDescription {
    static func describe(stage: Int) -> String {
        switch min(10, max(1, stage)) {
        case 1:
            return "bare soil"
        case 2:
            return "early sprouts"
        case 3:
            return "small seedlings"
        case 4:
            return "young plants"
        case 5:
            return "first blooms"
        case 6:
            return "half full garden"
        case 7:
            return "dense growth"
        case 8:
            return "abundant growth"
        case 9:
            return "overflowing bed"
        default:
            return "peak bloom"
        }
    }
}

private enum HarvestFoodDescription {
    static func describe(stage: Int) -> String {
        switch min(10, max(1, stage)) {
        case 1:
            return "bare table"
        case 2:
            return "sparse food"
        case 3:
            return "small serving"
        case 4:
            return "steady serving"
        case 5:
            return "half full table"
        case 6:
            return "growing spread"
        case 7:
            return "full spread"
        case 8:
            return "abundant spread"
        case 9:
            return "overflowing spread"
        default:
            return "harvest feast"
        }
    }
}
