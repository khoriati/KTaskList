import SwiftUI

/// Confirmação exibida dentro da própria view (não abre janela/sheet), pois
/// diálogos modais fazem o popover da barra de menu perder o foco e fechar.
struct InlineConfirmation: Identifiable {
    let id = UUID()
    var title: String
    var message: String
    var actionLabel: String = "Excluir"
    var action: () -> Void
}

extension View {
    func inlineConfirmation(_ confirmation: Binding<InlineConfirmation?>) -> some View {
        overlay(alignment: .bottom) {
            if let current = confirmation.wrappedValue {
                InlineConfirmationBar(confirmation: current) {
                    confirmation.wrappedValue = nil
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.15), value: confirmation.wrappedValue?.id)
    }
}

private struct InlineConfirmationBar: View {
    let confirmation: InlineConfirmation
    let dismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(confirmation.title, systemImage: "exclamationmark.triangle.fill")
                .font(.subheadline.weight(.semibold))
            Text(confirmation.message)
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button("Cancelar", action: dismiss)
                    .keyboardShortcut(.cancelAction)
                Button(confirmation.actionLabel, role: .destructive) {
                    confirmation.action()
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
            }
            .controlSize(.small)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10).fill(.regularMaterial))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.quaternary))
        .shadow(radius: 8, y: 2)
        .padding(12)
    }
}
