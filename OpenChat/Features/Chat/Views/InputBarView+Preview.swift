import SwiftUI

#Preview("Empty Composer") {
    VStack {
        Spacer()
        InputBarView(
            text: .constant(""),
            inputRole: .constant(.participant),
            responderIds: .constant([]),
            isGenerating: false,
            onSend: {},
            onStop: {},
            onCustomizeResponders: {}
        )
    }
    .background(OpenChatDesignSystem.Surface.pageBackground)
}

#Preview("Composer With Text") {
    VStack {
        Spacer()
        InputBarView(
            text: .constant("Hello, how are you?"),
            inputRole: .constant(.participant),
            responderIds: .constant([]),
            isGenerating: false,
            onSend: {},
            onStop: {},
            onCustomizeResponders: {}
        )
    }
    .background(OpenChatDesignSystem.Surface.pageBackground)
}

#Preview("Generating Composer") {
    VStack {
        Spacer()
        InputBarView(
            text: .constant(""),
            inputRole: .constant(.participant),
            responderIds: .constant([]),
            isGenerating: true,
            onSend: {},
            onStop: {},
            onCustomizeResponders: {}
        )
    }
    .background(OpenChatDesignSystem.Surface.pageBackground)
}
