import SwiftUI

struct EmojiRatingPicker: View {
    let field: MorningOutcomeField
    @Binding var value: Int?

    private let options: [(emoji: String, label: String, value: Int)] = [
        ("😌", "None", 0),
        ("🙂", "Mild", 3),
        ("😐", "Moderate", 5),
        ("😣", "Strong", 7),
        ("😫", "Severe", 10)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: TelocareTheme.Spacing.sm) {
            HStack {
                fieldIcon
                Text(field.displayTitle)
                    .font(TelocareTheme.Typography.headline)
                    .foregroundStyle(TelocareTheme.charcoal)
                Spacer()
                if let value {
                    selectedBadge(for: value)
                }
            }

            HStack(spacing: TelocareTheme.Spacing.sm) {
                ForEach(options, id: \.value) { item in
                    EmojiButton(
                        emoji: item.emoji,
                        label: item.label,
                        isSelected: value == item.value,
                        action: { value = item.value }
                    )
                }
            }
        }
        .padding(TelocareTheme.Spacing.md)
        .background(TelocareTheme.cream)
        .clipShape(RoundedRectangle(cornerRadius: TelocareTheme.CornerRadius.medium, style: .continuous))
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private var fieldIcon: some View {
        Image(systemName: field.systemImageName)
            .font(.system(size: 20, weight: .regular, design: .rounded))
            .foregroundStyle(TelocareTheme.coral)
            .frame(width: 28, height: 28)
    }

    @ViewBuilder
    private func selectedBadge(for selectedValue: Int) -> some View {
        let item = options.first { $0.value == selectedValue } ?? options[0]
        Text(item.label)
            .font(TelocareTheme.Typography.small)
            .foregroundStyle(TelocareTheme.coral)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(TelocareTheme.peach)
            .clipShape(Capsule())
    }
}

private struct EmojiButton: View {
    let emoji: String
    let label: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Text(emoji)
                    .font(.system(size: 28, weight: .regular, design: .rounded))
                Text(label)
                    .font(TelocareTheme.Typography.small)
                    .foregroundStyle(isSelected ? TelocareTheme.coral : TelocareTheme.warmGray)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, TelocareTheme.Spacing.sm)
            .background(
                RoundedRectangle(cornerRadius: TelocareTheme.CornerRadius.small, style: .continuous)
                    .fill(isSelected ? TelocareTheme.peach : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: TelocareTheme.CornerRadius.small, style: .continuous)
                    .stroke(isSelected ? TelocareTheme.coral : TelocareTheme.muted.opacity(0.3), lineWidth: isSelected ? 2 : 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(label): \(emoji)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
