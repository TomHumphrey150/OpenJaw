import SwiftUI

// MARK: - Detail Row Helper

struct DetailRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .font(TelocareTheme.Typography.caption)
                .foregroundStyle(TelocareTheme.warmGray)
            Spacer()
            Text(value)
                .font(TelocareTheme.Typography.body)
                .foregroundStyle(TelocareTheme.charcoal)
        }
    }
}

