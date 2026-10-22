import SwiftUI

/// Modo lista: outline com todos os níveis.
struct TaskOutlineView: View {
    @EnvironmentObject private var store: TaskStore
    let roots: [TaskItem]
    @Binding var path: [Route]
    let askDelete: (TaskItem) -> Void

    var body: some View {
        List(roots, children: \.outlineChildren) { task in
            TaskRow(task: task) {
                path.append(.detail(task.id))
            } toggle: {
                store.toggleDone(id: task.id)
            }
            .contextMenu {
                Button("Abrir") { path.append(.detail(task.id)) }
                Button(task.isDone ? "Reabrir" : "Concluir") { store.toggleDone(id: task.id) }
                Divider()
                Button("Mover para cima") { store.shift(task.id, by: -1) }
                Button("Mover para baixo") { store.shift(task.id, by: 1) }
                Divider()
                Button("Excluir", role: .destructive) { askDelete(task) }
            }
        }
        .listStyle(.plain)
    }
}

// MARK: - Linha

struct TaskRow: View {
    let task: TaskItem
    let open: () -> Void
    let toggle: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Button(action: toggle) {
                Image(systemName: task.isDone ? "checkmark.circle.fill" : "circle")
                    .imageScale(.large)
                    .foregroundStyle(task.isDone ? Color.accentColor : Color.secondary)
            }
            .buttonStyle(.plain)

            Button(action: open) {
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(task.title)
                            .strikethrough(task.isDone)
                            .foregroundStyle(task.isDone ? .secondary : .primary)
                            .lineLimit(1)
                        if !task.notes.isEmpty {
                            Text(MarkdownConverter.plainText(fromMarkdown: task.notes))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                    Spacer(minLength: 4)
                    TaskBadges(task: task, compact: false)
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 2)
    }
}

/// Ícones de estado de um item: lembrete, atraso, sub-itens e anexos.
struct TaskBadges: View {
    let task: TaskItem
    /// Modo compacto (cards): só ícones e números curtos.
    var compact = true

    var body: some View {
        HStack(spacing: compact ? 5 : 6) {
            if task.isLate() {
                Label(compact ? task.reminder?.lateDescription() ?? "" : "Atrasado \(task.reminder?.lateDescription() ?? "")",
                      systemImage: "clock.badge.exclamationmark")
                    .foregroundStyle(.red)
                    .help("Atrasado: planejado para \(task.reminder?.label ?? "")")
            } else if let reminder = task.reminder, !task.isDone {
                Label(reminder.label, systemImage: reminder.hasTime ? "bell" : "calendar")
                    .foregroundStyle(reminder.isPending ? Color.secondary : Color.secondary.opacity(0.6))
                    .help(reminder.hasTime ? "Lembrete com horário" : "Lembrete do dia")
            }
            if !task.subtasks.isEmpty {
                Label("\(task.doneSubtasks)/\(task.subtasks.count)", systemImage: "list.bullet.indent")
                    .help("Sub-itens concluídos / total")
            }
            if task.totalAttachments > 0 {
                Label("\(task.totalAttachments)", systemImage: "paperclip")
                    .help("Anexos (inclui sub-itens)")
            }
        }
        .font(compact ? .caption2 : .caption)
        .foregroundStyle(.secondary)
        .labelStyle(.titleAndIcon)
        .lineLimit(1)
    }
}
