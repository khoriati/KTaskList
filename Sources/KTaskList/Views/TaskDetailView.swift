import SwiftUI

/// Detalhe de um item em qualquer nível da árvore: título, notas, lembrete,
/// anexos e sub-itens (enquanto o limite de níveis permitir).
struct TaskDetailView: View {
    @EnvironmentObject private var store: TaskStore
    @EnvironmentObject private var settings: AppSettings
    @Binding var task: TaskItem
    @Binding var path: [Route]

    @State private var newSubtitle = ""
    @State private var confirmation: InlineConfirmation?
    @FocusState private var titleFocused: Bool
    /// Último título não vazio, restaurado se o usuário apagar tudo e sair do campo.
    @State private var lastNonEmptyTitle = ""

    private var depth: Int { store.depth(of: task.id) ?? 0 }
    private var isSubtask: Bool { depth > 0 }
    private var canAddChild: Bool { depth < settings.maxSubLevels }
    private var ancestors: [TaskItem] { store.ancestors(of: task.id) }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    titleSection
                    notesSection
                    reminderSection
                    AttachmentsSection(attachments: $task.attachments)
                    subtasksSection
                    footer
                }
                .padding(14)
            }
        }
        .inlineConfirmation($confirmation)
    }

    private func askDelete() {
        confirmation = InlineConfirmation(
            title: isSubtask ? "Excluir este sub-item?" : "Excluir esta tarefa?",
            message: task.subtasks.isEmpty
                ? "Os anexos do item serão apagados."
                : "Sub-itens e anexos também serão apagados.",
            action: deleteSelf
        )
    }

    // MARK: - Seções

    private var header: some View {
        HStack(spacing: 8) {
            Button {
                if !path.isEmpty { path.removeLast() }
            } label: {
                Label("Voltar", systemImage: "chevron.left")
            }
            .buttonStyle(.borderless)
            .keyboardShortcut(.cancelAction)

            Spacer()
            breadcrumb
            Spacer()

            Button(role: .destructive, action: askDelete) {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .help(isSubtask ? "Excluir sub-item" : "Excluir tarefa")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    /// Caminho até o item: "Raiz › Pai" com o nível atual.
    private var breadcrumb: some View {
        HStack(spacing: 4) {
            if ancestors.isEmpty {
                Text("Item raiz")
            } else {
                ForEach(ancestors) { ancestor in
                    Button(ancestor.title) { path.append(.detail(ancestor.id)) }
                        .buttonStyle(.plain)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .frame(maxWidth: 110)
                    Image(systemName: "chevron.right").font(.caption2)
                }
                Text("Nível \(depth)")
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    private var titleSection: some View {
        HStack(alignment: .top, spacing: 10) {
            Button { task.isDone.toggle() } label: {
                Image(systemName: task.isDone ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundStyle(task.isDone ? Color.accentColor : Color.secondary)
            }
            .buttonStyle(.plain)
            .padding(.top, 3)

            TextField("Título", text: $task.title, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.title3.weight(.semibold))
                .strikethrough(task.isDone)
                .focused($titleFocused)
                .lineLimit(1...4)
                .onAppear { lastNonEmptyTitle = task.title }
                .onChange(of: task.title) { _, title in
                    if !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { lastNonEmptyTitle = title }
                }
                .onChange(of: titleFocused) { _, focused in
                    if !focused, task.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        task.title = lastNonEmptyTitle
                    }
                }
        }
    }

    private var notesSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionTitle("Notas", systemImage: "note.text")
            MarkdownEditor(markdown: $task.notes)
        }
    }

    private var reminderSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                SectionTitle("Lembrete", systemImage: "bell")
                Spacer()
                Toggle("", isOn: reminderEnabled)
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .labelsHidden()
            }

            if let reminder = task.reminder {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 12) {
                        DatePicker(
                            "Data",
                            selection: reminderDate,
                            displayedComponents: reminder.hasTime ? [.date, .hourAndMinute] : [.date]
                        )
                        .datePickerStyle(.field)
                        .labelsHidden()
                        Toggle("Com horário", isOn: reminderHasTime)
                            .controlSize(.small)
                    }

                    Text(reminder.hasTime
                         ? "O alerta abre na data e hora indicadas."
                         : "O alerta abre quando você fizer login ou desbloquear o Mac nesse dia.")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)

                    if let seen = reminder.acknowledgedAt {
                        HStack(spacing: 8) {
                            Label("Dispensado em \(seen.isoShort) · volta no próximo login/desbloqueio", systemImage: "clock.arrow.circlepath")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Button("Reativar") { task.reminder?.acknowledgedAt = nil }
                                .controlSize(.mini)
                        }
                    } else if task.hasOverdueReminder() {
                        Label("Vencido", systemImage: "exclamationmark.circle")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 8).fill(.quaternary.opacity(0.4)))
            }
        }
    }

    // Bindings do lembrete: qualquer edição volta o lembrete para pendente.

    private var reminderEnabled: Binding<Bool> {
        Binding(
            get: { task.reminder != nil },
            set: { task.reminder = $0 ? .defaultValue() : nil }
        )
    }

    private var reminderDate: Binding<Date> {
        Binding(
            get: { task.reminder?.date ?? Date() },
            set: { newDate in
                task.reminder?.date = newDate
                task.reminder?.acknowledgedAt = nil
            }
        )
    }

    private var reminderHasTime: Binding<Bool> {
        Binding(
            get: { task.reminder?.hasTime ?? false },
            set: { hasTime in
                guard var r = task.reminder else { return }
                r.hasTime = hasTime
                r.acknowledgedAt = nil
                if hasTime {
                    // Ao ligar o horário, propõe 09:00 se a hora ainda não foi definida.
                    let cal = Calendar.current
                    let comps = cal.dateComponents([.hour, .minute], from: r.date)
                    if comps.hour == 0 && comps.minute == 0 {
                        r.date = cal.date(bySettingHour: 9, minute: 0, second: 0, of: r.date) ?? r.date
                    }
                }
                task.reminder = r
            }
        )
    }

    private var subtasksSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                SectionTitle("Sub-itens", systemImage: "list.bullet.indent")
                Spacer()
                if !task.subtasks.isEmpty {
                    Text("\(task.doneSubtasks)/\(task.subtasks.count)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if !task.subtasks.isEmpty {
                ProgressView(value: Double(task.doneSubtasks), total: Double(task.subtasks.count))
                    .controlSize(.small)
            }

            VStack(spacing: 0) {
                ForEach($task.subtasks) { $sub in
                    SubtaskRow(sub: $sub) {
                        path.append(.detail(sub.id))
                    } delete: {
                        store.deleteTask(id: sub.id)
                    }
                    if sub.id != task.subtasks.last?.id {
                        Divider().padding(.leading, 30)
                    }
                }
            }
            .background(RoundedRectangle(cornerRadius: 8).fill(.quaternary.opacity(0.4)))

            if canAddChild {
                HStack(spacing: 8) {
                    TextField("Novo sub-item…", text: $newSubtitle)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit(addSubtask)
                    Button(action: addSubtask) {
                        Image(systemName: "plus.circle.fill").imageScale(.large)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(newSubtitle.trimmingCharacters(in: .whitespaces).isEmpty ? .secondary : Color.accentColor)
                    .disabled(newSubtitle.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            } else {
                Label("Limite de \(settings.maxSubLevels) sub-níveis atingido (ajustável em Configurações).",
                      systemImage: "info.circle")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private var footer: some View {
        Text("Criado em \(task.createdAt.isoShort)")
            .font(.caption2)
            .foregroundStyle(.tertiary)
            .padding(.top, 6)
    }

    // MARK: - Ações

    private func addSubtask() {
        guard store.addSubtask(to: task.id, title: newSubtitle) != nil else { return }
        newSubtitle = ""
    }

    private func deleteSelf() {
        store.deleteTask(id: task.id)
        if !path.isEmpty { path.removeLast() }
    }
}

// MARK: - Componentes

struct SectionTitle: View {
    let title: String
    let systemImage: String

    init(_ title: String, systemImage: String) {
        self.title = title
        self.systemImage = systemImage
    }

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.secondary)
    }
}

private struct SubtaskRow: View {
    @Binding var sub: TaskItem
    let open: () -> Void
    let delete: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Button { sub.isDone.toggle() } label: {
                Image(systemName: sub.isDone ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(sub.isDone ? Color.accentColor : Color.secondary)
            }
            .buttonStyle(.plain)

            Button(action: open) {
                HStack(spacing: 6) {
                    Text(sub.title)
                        .strikethrough(sub.isDone)
                        .foregroundStyle(sub.isDone ? .secondary : .primary)
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    TaskBadges(task: sub, compact: false)
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .contextMenu {
            Button("Abrir", action: open)
            Button(sub.isDone ? "Reabrir" : "Concluir") { sub.isDone.toggle() }
            Divider()
            Button("Excluir", role: .destructive, action: delete)
        }
    }
}
