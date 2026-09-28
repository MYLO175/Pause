import SwiftUI

enum Palette {
    static let cream = Color(red: 0.97, green: 0.95, blue: 0.91)
    static let paper = Color(red: 0.995, green: 0.983, blue: 0.955)
    static let ink = Color(red: 0.20, green: 0.23, blue: 0.20)
    static let secondary = Color(red: 0.43, green: 0.45, blue: 0.40)
    static let sage = Color(red: 0.38, green: 0.46, blue: 0.36)
    static let dialSage = Color(red: 0.40, green: 0.49, blue: 0.48)
    static let pale = Color(red: 0.87, green: 0.88, blue: 0.81)
    static let line = Color(red: 0.86, green: 0.85, blue: 0.79)
    static let clay = Color(red: 0.64, green: 0.39, blue: 0.28)
}

struct MeditationLandscapeBackground: View {
    var body: some View {
        GeometryReader { geometry in
            Image("MeditationLandscape")
                .resizable()
                .scaledToFill()
                .frame(width: geometry.size.width, height: geometry.size.height, alignment: .trailing)
                .clipped()
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .ignoresSafeArea()
    }
}

extension View {
    func eyebrow() -> some View { font(.system(size: 10, weight: .semibold, design: .rounded)).tracking(2.5).foregroundStyle(Palette.secondary) }
    func paperCard() -> some View {
        padding(20)
            .background(Palette.paper, in: RoundedRectangle(cornerRadius: 24))
            .overlay(RoundedRectangle(cornerRadius: 24).strokeBorder(Palette.line.opacity(0.38), lineWidth: 0.8))
            .shadow(color: Palette.ink.opacity(0.035), radius: 12, x: 0, y: 4)
    }
    func pauseFormSurface() -> some View {
        self
            .scrollContentBackground(.hidden)
            .background(Palette.cream)
            .foregroundStyle(Palette.ink)
            .font(.system(.body, design: .rounded))
            .tint(Palette.dialSage)
            .listStyle(.insetGrouped)
            .toolbarBackground(Palette.cream, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
    }
}
struct PauseSectionHeader: View {
    let title: String
    var body: some View {
        Text(title)
            .font(.system(size: 14, weight: .regular, design: .serif))
            .textCase(nil)
            .foregroundStyle(Palette.secondary)
    }
}
struct PauseSectionFooter: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.system(size: 12, weight: .regular, design: .rounded))
            .foregroundStyle(Palette.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}
struct PrimaryButton: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.system(.body, design: .rounded).weight(.medium))
            .frame(maxWidth: .infinity).padding(.vertical, 19)
            .background(Palette.ink.opacity(configuration.isPressed ? 0.82 : 1), in: Capsule())
            .foregroundStyle(Palette.paper)
    }
}
struct CircleButton: View {
    let symbol: String
    let label: String
    var action: () -> Void
    var body: some View {
        Button(action: action) { Image(systemName: symbol).font(.system(size: 17, weight: .regular)).frame(width: 44, height: 44).background(Palette.paper, in: Circle()) }
            .accessibilityLabel(label)
    }
}
func durationText(_ seconds: Double) -> String {
    let total = max(0, Int(ceil(seconds)))
    return String(format: "%02d:%02d", total / 60, total % 60)
}
func minutesText(_ seconds: Double) -> String {
    if seconds < 60 { return "\(Int(seconds)) sec" }
    return "\(Int(seconds / 60)) min"
}
