//
//  SleepView.swift
//  Skywalker-Watch Watch App
//
//  Minimal black screen for sleep - shows only essential info
//

import SwiftUI

struct SleepView: View {
    @State var connectivityManager: WatchConnectivityManager

    var body: some View {
        ZStack {
            // Pure black background
            Color.black
                .ignoresSafeArea()

            VStack(spacing: 20) {
                // Minimal connection indicator (dim)
                Circle()
                    .fill(connectivityManager.isConnectedToPhone ? Color.green.opacity(0.3) : Color.red.opacity(0.3))
                    .frame(width: 8, height: 8)

                // Event count (dim, only show if events occurred)
                if connectivityManager.totalEvents > 0 {
                    Text("\(connectivityManager.totalEvents)")
                        .font(.system(size: 24, weight: .light, design: .rounded))
                        .foregroundColor(.white.opacity(0.2))
                }

                Spacer()

                // Hint to swipe for debug view (very dim)
                Text("↓ debug")
                    .font(.system(size: 10))
                    .foregroundColor(.white.opacity(0.1))
            }
            .padding(.top, 40)
            .padding(.bottom, 10)
        }
    }
}

#Preview {
    SleepView(connectivityManager: WatchConnectivityManager())
}
