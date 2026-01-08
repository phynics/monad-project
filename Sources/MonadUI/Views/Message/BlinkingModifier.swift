import SwiftUI

public struct BlinkingModifier: ViewModifier {
    @State private var isVisible = true

    public init() {}

    public func body(content: Content) -> some View {
        content
            .opacity(isVisible ? 1.0 : 0.0)
            .onAppear {
                withAnimation(Animation.easeInOut(duration: 0.6).repeatForever(autoreverses: true))
                {
                    isVisible.toggle()
                }
            }
    }
}
