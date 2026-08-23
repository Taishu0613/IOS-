//
//  ToastModifier.swift
//  WAGhack
//

import SwiftUI

// 画面下部に一時的にメッセージを表示する、スナックバーのようなUIパーツ
struct ToastModifier: ViewModifier {
    @Binding var message: String?

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .bottom) {
                if let message {
                    Text(message)
                        .font(.subheadline)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(.black.opacity(0.8), in: Capsule())
                        .padding(.bottom, 24)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .task(id: message) {
                            // 表示してから一定時間経ったら自動的に消す
                            try? await Task.sleep(for: .seconds(2))
                            withAnimation {
                                self.message = nil
                            }
                        }
                }
            }
            .animation(.spring(duration: 0.3), value: message)
    }
}

extension View {
    // 一時的な通知メッセージ（スナックバー）を表示するためのモディファイア
    func toast(message: Binding<String?>) -> some View {
        modifier(ToastModifier(message: message))
    }
}
