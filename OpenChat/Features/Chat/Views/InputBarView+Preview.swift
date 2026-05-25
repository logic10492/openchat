import SwiftUI

#Preview("Empty Composer") {
    VStack {
        Spacer()
        InputBarView(
            text: .constant(""),
            isPrefillModeEnabled: .constant(false),
            inputRole: .constant(.participant),
            responderIds: .constant([]),
            prefillNextRole: .userMessage,
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
            isPrefillModeEnabled: .constant(false),
            inputRole: .constant(.participant),
            responderIds: .constant([]),
            prefillNextRole: .userMessage,
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
            isPrefillModeEnabled: .constant(false),
            inputRole: .constant(.participant),
            responderIds: .constant([]),
            prefillNextRole: .userMessage,
            isGenerating: true,
            onSend: {},
            onStop: {},
            onCustomizeResponders: {}
        )
    }
    .background(OpenChatDesignSystem.Surface.pageBackground)
}

#Preview("Prefill Composer") {
    VStack {
        Spacer()
        InputBarView(
            text: .constant("I already know the first answer."),
            isPrefillModeEnabled: .constant(true),
            inputRole: .constant(.participant),
            responderIds: .constant([]),
            prefillNextRole: .assistantReply,
            isGenerating: false,
            onSend: {},
            onStop: {},
            onCustomizeResponders: {}
        )
    }
    .background(OpenChatDesignSystem.Surface.pageBackground)
}
