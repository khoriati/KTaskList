import SwiftUI

/// Conteúdo da janela de alerta: lista dos lembretes vencidos com ações.
struct ReminderAlertView: View {
    @EnvironmentObject private var store: TaskStore
    @EnvironmentObject private var scheduler: ReminderScheduler

    private var items: [TaskItem] {
        scheduler.presentedIDs.compactMap(store.find)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(spacing: 10) {
                    ForEach(items) { task in
                        ReminderAlertRow(task: task)
                    }
                }
                .padding(12)
            }
            Divider()
            footer
        }
        .frame(minWidth: 360, minHeight: 220)
        .background(.background)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "bell.badge.fill")
                .foregroundStyle(.orange)
                .font(.title3)
            Text(items.count == 1 ? "Lembrete" : "\(items.count) lembretes")
                .font(.headline)
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.top, 30)
        .padding(.bottom, 10)
    }

    private var footer: some View {
        HStack {
            Text("OK ou fechar esconde até o próximo login/desbloqueio. Só concluir encerra.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
            Spacer()
            if items.count > 1 {
                Button("Dispensar todos") { scheduler.dismissAll() }
                    .controlSize(.small)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}

private struct ReminderAlertRow: View {
    @EnvironmentObject private var scheduler: ReminderScheduler
    let task: TaskItem

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(task.title)
                .font(.body.weight(.semibold))
                .lineLimit(2)
            if !task.notes.isEmpty {
                Text(task.notes)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            if let reminder = task.reminder {
                Label(reminder.label, systemImage: reminder.hasTime ? "clock" : "calendar")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
            HStack(spacing: 8) {
                Button("Abrir", systemImage: "arrow.up.forward.square") { scheduler.open(task.id) }
                Menu("Adiar", systemImage: "zzz") {
                    Button("10 minutos") { scheduler.snooze(task.id, by: 10 * 60) }
                    Button("1 hora") { scheduler.snooze(task.id, by: 60 * 60) }
                    Button("3 horas") { scheduler.snooze(task.id, by: 3 * 60 * 60) }
                    Button("Amanhã às 09:00") { scheduler.snoozeUntilTomorrowMorning(task.id) }
                }
                .fixedSize()
                Spacer()
                Button("Concluir", systemImage: "checkmark.circle") { scheduler.complete(task.id) }
                Button("OK") { scheduler.acknowledge(task.id) }
                    .buttonStyle(.borderedProminent)
            }
            .controlSize(.small)
            .padding(.top, 2)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10).fill(.quaternary.opacity(0.4)))
    }
}
