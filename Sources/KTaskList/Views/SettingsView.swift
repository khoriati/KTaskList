import SwiftUI

/// Janela de Configurações (⌘,).
struct SettingsView: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var store: TaskStore

    var body: some View {
        Form {
            Section("Estrutura") {
                Stepper(value: $settings.maxSubLevels, in: AppSettings.subLevelsRange) {
                    LabeledContent("Sub-níveis permitidos", value: "\(settings.maxSubLevels)")
                }
                Text("Itens raiz podem ter sub-itens até \(settings.maxSubLevels) nível(is) abaixo. Reduzir o limite não apaga itens existentes, apenas impede criar/mover para mais fundo.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("Exibição") {
                Toggle("Mostrar itens concluídos", isOn: $settings.showCompleted)
                Picker("Visualização padrão", selection: $settings.viewMode) {
                    ForEach(AppSettings.ViewMode.allCases) { mode in
                        Label(mode.title, systemImage: mode.systemImage).tag(mode)
                    }
                }
                Slider(value: $settings.mapZoom, in: AppSettings.zoomRange, step: AppSettings.zoomStep) {
                    Text("Zoom do mapa (\(Int((settings.mapZoom * 100).rounded()))%)")
                }
            }
            Section("Dados") {
                LabeledContent("Pasta") {
                    Text(store.baseDirectory.path)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .truncationMode(.middle)
                }
                Button("Mostrar no Finder") { store.revealDataFolder() }
            }
        }
        .formStyle(.grouped)
        .frame(width: 440)
        .fixedSize(horizontal: false, vertical: true)
    }
}
