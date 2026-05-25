import SwiftUI

struct VibeBackgroundShade: View {
    let colorScheme: ColorScheme
    let reduceTransparency: Bool

    var body: some View {
        ZStack {
            if colorScheme == .dark {
                RadialGradient(
                    colors: [
                        Color.orange.opacity(0.18),
                        Color.clear,
                    ],
                    center: UnitPoint(x: 0.50, y: 0.88),
                    startRadius: 0,
                    endRadius: 260
                )
                LinearGradient(
                    colors: [
                        Color(red: 0.02, green: 0.02, blue: 0.04).opacity(0.18),
                        Color(red: 0.02, green: 0.02, blue: 0.04).opacity(reduceTransparency ? 0.82 : 0.62),
                        Color(red: 0.02, green: 0.02, blue: 0.04).opacity(reduceTransparency ? 0.90 : 0.82),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            } else {
                RadialGradient(
                    colors: [
                        Color(red: 1.00, green: 0.73, blue: 0.37).opacity(0.20),
                        Color.clear,
                    ],
                    center: UnitPoint(x: 0.47, y: 0.88),
                    startRadius: 0,
                    endRadius: 280
                )
                LinearGradient(
                    colors: [
                        Color(red: 1.00, green: 0.98, blue: 0.94).opacity(0.06),
                        Color(red: 1.00, green: 0.98, blue: 0.94).opacity(reduceTransparency ? 0.54 : 0.28),
                        Color(red: 0.98, green: 0.93, blue: 0.86).opacity(reduceTransparency ? 0.66 : 0.46),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
        }
    }
}
