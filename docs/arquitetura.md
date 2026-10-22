# Arquitetura do KTaskList

Este documento descreve como o app é organizado, por onde os dados fluem e quais
decisões de projeto sustentam o código. Leia-o antes de alterar qualquer módulo.

## Visão geral

```
┌──────────────────────────── Cenas (KTaskListApp) ────────────────────────────┐
│ MenuBarExtra(.window)        Window "Tarefas" (destacada)        Settings     │
│        └── RootView ──────────────┘                                            │
│              └── NavigationStack[Route] → HomeView → TaskDetailView            │
└──────────────────────────────────────┬───────────────────────────────────────┘
                                       │ @EnvironmentObject
          ┌────────────────────────────┼─────────────────────────────┐
          ▼                            ▼                             ▼
   TaskStore (@MainActor)        AppSettings (@MainActor)     ReminderScheduler
   fonte da verdade              preferências (UserDefaults)  timer + eventos de sessão
   [TaskItem] + anexos                                        ReminderAlertWindow
          │ JSON atômico                                      DetachedWindows / TaskWindows
          ▼
   ~/Library/Application Support/KTaskList/{tasks.json, tasks.backup.json, Attachments/}

   Lógica pura (sem UI, testada):  Models.swift · MindMapLayout.swift · MarkdownConverter.swift
```

Três camadas, sem framework além de SwiftUI/AppKit:

| Camada | Arquivos | Regra |
|---|---|---|
| **Domínio** (puro) | `Models.swift`, `MindMapLayout.swift`, `MarkdownConverter.swift` | Sem estado global, sem AppKit além de `NSAttributedString`/`NSFont`; tudo testável com XCTest. |
| **Aplicação / estado** | `TaskStore.swift`, `AppSettings.swift`, `ReminderScheduler.swift` | `ObservableObject`s `@MainActor`. Toda mutação de dados passa por aqui. |
| **Interface** | `KTaskListApp.swift`, `Views/*` | SwiftUI; AppKit onde SwiftUI não chega (NSTextView, janelas de alerta, drag-and-drop). Nunca muta `TaskItem` diretamente. |

## Modelo de dados

`TaskItem` é uma árvore recursiva (`subtasks: [TaskItem]`). A mesma struct serve
a qualquer nível: raiz e sub-item só diferem pela posição. Operações por **caminho
de índices** (`[Int]`) em `Array<TaskItem>` (`indexPath(of:)`, `subscript(path:)`,
`remove(atPath:)`) permitem localizar, alterar e remover em qualquer profundidade
sem referências nem identidade de classe. Tudo é `struct`/`Codable`/`Hashable`,
o que torna o diff de estado do SwiftUI barato e o JSON trivial.

`Reminder` distingue dois instantes:

- `fireDate`: quando o **alerta** dispara (hora exata ou início do dia).
- `deadline`: quando o item passa a contar como **atrasado** (hora exata ou fim do dia).

`acknowledgedAt` registra que o alerta foi dispensado; não altera o atraso.

`Attachment` guarda só metadados; o arquivo vive em `Attachments/<uuid>.<ext>`.

Detalhes do JSON em [formato-de-dados.md](formato-de-dados.md).

## TaskStore: fonte da verdade

- `@Published var tasks: [TaskItem]` é o estado. Qualquer `didSet` (fora do
  carregamento inicial) agenda uma gravação com **debounce de 300 ms**
  (`scheduleSave`); `save()` grava com `.atomic` (arquivo temporário + rename,
  nunca um JSON pela metade). `flushPendingSave()` grava na hora e é chamado em
  `NSApplication.willTerminateNotification`, para que Sair/logout não perca a
  última alteração.
- `load()` lê uma vez no `init`; se decodificar com sucesso, grava
  `tasks.backup.json` antes de expor os dados. Se falhar, copia o arquivo para
  `tasks.corrupt-<data>.json`, marca `loadFailed`, loga o motivo e começa vazio.
  A decodificação é tolerante: só `title`, `fileName`/`displayName` e
  `date` são obrigatórios (`init(from:)` manual em `Models.swift`).
- Rascunhos da edição inline ficam em `draftIDs`. Só eles são removidos ao
  confirmar um título vazio; um item real com o título apagado mantém o
  anterior (no detalhe, `TaskDetailView` restaura ao perder o foco).
- API de consulta: `find`, `depth(of:)`, `ancestors(of:)`, `parentID(of:)`,
  `canAddChild(to:)`, `binding(for:)` (para a tela de detalhe editar in-place).
- API de alteração: `update(_:_:)` (mutação por id em qualquer nível), `addTask`,
  `addSubtask`, `insertDraft`/`commitTitle`/`discardDraft` (edição inline),
  `deleteTask`, `toggleDone`, `clearCompleted`.
- Movimentação: `canMove(_:toParent:)` e `canMove(_:besides:)` devolvem um
  `MoveCheck` (`.ok`, `.sameParent`, `.intoItself`, `.tooDeep`, `.notFound`) que as views
  usam para colorir o alvo do arrasto **antes** de soltar; `move(_:toParent:)`,
  `move(_:besides:after:)` e `shift(_:by:)` executam. O limite de níveis
  considera a **altura da sub-árvore movida** (`subtreeHeight`), não só o item.
- Anexos: `importFile(from:)` copia o arquivo para a pasta de anexos com nome
  `<uuid>.<ext>`; `importData` grava bytes (imagem colada); `deleteFile` apaga a
  cópia. `deleteTask` apaga os anexos de toda a sub-árvore removida e limpa os
  ids recolhidos em `AppSettings`.
- Pasta de dados: `KTASKLIST_DATA_DIR` ou parâmetro `baseDirectory` no `init`
  (usado pelos testes). Se a pasta nova não existe e a antiga `TaskList/` contém
  um `tasks.json`, ela é renomeada para `KTaskList/` (a checagem do `tasks.json`
  evita mover a pasta de outro app com o mesmo nome).
- `fileURL(for:)` usa só o último componente de `fileName`: um JSON editado por
  fora não consegue apontar (nem apagar) nada fora de `Attachments/`.

## AppSettings

Preferências em `UserDefaults`, cada `@Published` com `didSet` gravando a chave
correspondente. `maxSubLevels` e `mapZoom` são **clampados** no `didSet` (um valor
fora da faixa é corrigido e regravado). `collapsedIDs` guarda os nós recolhidos
do mapa. `matchesFilter(_:)` concentra a regra dos filtros rápidos.

## Mapa mental

`MindMapLayout.compute(roots:metrics:collapsed:)` é uma **função pura**: recebe a
floresta já filtrada e devolve `nodes` (frame, profundidade, índice da raiz, se
está recolhido e quantos descendentes esconde) e `edges` (pontos de origem e
destino dos conectores). Regras:

- Colunas por profundidade; cada pai fica centralizado verticalmente nos filhos.
- Árvores (raízes) empilhadas; a cor vem de `MindMapPalette.color(for: rootIndex)`.
- Nó recolhido ocupa uma linha e reporta `hiddenDescendants`.

`MindMapCanvasView` renderiza o resultado em um `ZStack` dentro de `ScrollView`
nas duas direções, aplica `scaleEffect` para o zoom e trata seleção, hover,
teclado (`onKeyPress`) e drag-and-drop. `TaskCardView` é o card individual:
botões de concluir, + (sub-item) e recolher, zonas de soltura (`CardDropZone`:
antes / filho / depois, pela posição vertical do cursor) e o `InlineTitleEditor`.

### Drag-and-drop

O arrasto transporta apenas o **UUID** do item como texto (`NSItemProvider`).
Na soltura, `handleDrop` resolve o alvo (`.root` ou `.card(id, zone)`) e chama o
store, que valida de novo. A validação visual durante o arrasto usa `dropCheck`
com o `draggingID` em estado da view.

### Edição inline e foco

O card entra em modo de edição quando `editingID == id` **ou** o item está em
`store.draftIDs` (rascunho recém-criado por `insertDraft`). `InlineTitleEditor` pede foco
em várias tentativas curtas (0, 40, 120, 300 e 600 ms) porque o `NSTextField`
pode entrar na hierarquia um ciclo depois do card, e ativa o app
(`NSApp.activate`) porque o painel da barra de menu de um app `LSUIElement` não o
faz. A perda de foco só confirma o título **se o campo já teve foco**; assim uma
tentativa falha não apaga o rascunho. `select()` não devolve o foco ao canvas
enquanto há edição em curso.

## Editor de notas (Markdown WYSIWYG)

O modelo das notas é **Markdown** (`TaskItem.notes`). O editor
(`MarkdownEditor.swift`) é um `NSTextView` dentro de `NSViewRepresentable`:

- Ao carregar ou colar, `MarkdownConverter.attributedString(fromMarkdown:)`
  produz um `NSAttributedString` cujos parágrafos carregam o atributo
  `.mdBlock` (`MarkdownBlock`: p, h1–h3, quote, code) e trechos de código inline
  o atributo `.mdCode`. Negrito/itálico vêm dos traits da fonte; tachado e links,
  dos atributos padrão.
- A cada alteração, `MarkdownConverter.markdown(from:)` serializa de volta.
  Os testes de ida e volta (`MarkdownConverterTests`) garantem que o subconjunto
  suportado sobrevive à conversão.
- `MarkdownInputRule` reconhece prefixos de linha e marcadores inline enquanto
  o usuário digita (`MarkdownInputRuleTests`).

Subconjunto suportado: títulos 1–3, parágrafos, negrito, itálico, tachado,
código inline, bloco de código (sem linguagem), listas com marcador e numeradas
(com aninhamento), citação e links `[texto](url)` com esquema `http`, `https`
ou `mailto` (outros esquemas não abrem ao clicar nem podem ser inseridos).

**Atenção, conversão com perda:** o editor serializa o documento inteiro a cada
alteração. Construções fora do subconjunto são normalizadas na primeira tecla:
títulos 4–6 viram título 3, `---` vira texto, imagens ficam só com o texto
alternativo, tabelas e HTML viram texto corrido, quebras duras viram parágrafos.
Notas geradas por fora com essas construções devem ser consideradas "somente
leitura" dentro do app. Ampliar o subconjunto é uma contribuição bem-vinda
(ver [Limitações conhecidas](#limitações-conhecidas)).

## Lembretes

`ReminderScheduler` observa o store e decide quando apresentar alertas:

- Um `Timer` a cada 20 s verifica lembretes **com horário** (`fireDate <= now`).
- Lembretes **só do dia** aparecem apenas nas "oportunidades": abertura do app,
  `NSWorkspace.sessionDidBecomeActiveNotification`, `didWakeNotification`,
  `screensDidWakeNotification` e a notificação distribuída
  `com.apple.screenIsUnlocked`.
- O `Timer` roda no modo `.common` do run loop, para continuar disparando com
  menus abertos ou arrasto em curso. Os observers são removidos no `deinit`.
- A apresentação é uma **janela própria** (`ReminderAlertWindow` +
  `ReminderAlertView`), não `UNUserNotificationCenter`: notificações do sistema
  exigem bundle assinado por desenvolvedor identificado e permissão do usuário,
  o que não combina com um app compilado localmente.
- Dispensar (`acknowledge`) grava `acknowledgedAt`, mas o lembrete volta na
  próxima oportunidade enquanto o item estiver aberto. Adiar (`snooze`)
  reagenda sempre **com horário**. Concluir marca o item. `presentedIDs` alimenta
  o ícone de sino na barra de menu.

## Janelas

- `MenuBarExtra(.window)` é o popover. Ao aparecer, fecha janelas destacadas e
  ativa o app.
- `Window("Tarefas")` é a janela destacada, aberta por `HomeView.detach()` via
  `openWindow`; abrir uma fecha o popover (`DetachedWindows`).
- `TaskWindows` abre a tela de um item a partir do alerta, que não vive em uma
  cena SwiftUI e por isso não tem `openWindow`.

## Decisões de projeto (e por que não mudar sem discutir)

| Decisão | Motivo |
|---|---|
| JSON local, um arquivo, legível | Portabilidade, backup trivial, edição manual, zero dependência. SQLite/Core Data trariam migrações e opacidade sem ganho nesse volume. |
| Árvore de `struct`s com caminho de índices | Valor semântico (undo/diff simples), sem ciclos de referência, Codable gratuito. |
| Janela de alerta própria | Funciona sem assinatura de desenvolvedor nem permissão de notificações. |
| Sem `.xcodeproj` | `Package.swift` basta; CI e agentes usam só `swift build`/`swift test`. |
| `-parse-as-library` no target | Permite `@main` em um executável SPM sem `main.swift`. |
| Sem dependências externas | Build reproduzível em qualquer Mac com as Command Line Tools. |

## Pontos de extensão

- **Novo campo no item**: adicione em `TaskItem` com valor padrão, exponha em
  `TaskDetailView`, documente em `formato-de-dados.md`.
- **Nova visão**: crie `Views/MinhaView.swift` consumindo `store.tasks` filtrado
  por `settings.matchesFilter`, registre em `AppSettings.ViewMode` e no seletor
  de `HomeView`.
- **Novo tipo de filtro**: regra em `AppSettings.matchesFilter`, chip em
  `HomeView`, contador em `TaskStore`.
- **Exportação/importação**: trabalhe sobre `[TaskItem]` codificado; o encoder
  usado em `TaskStore.save()` (ISO 8601, chaves ordenadas) é a referência.
- **Sincronização**: fora do escopo atual; se vier, deve ser um adaptador em
  cima do JSON, nunca substituindo o `TaskStore`.

## Limitações conhecidas

Pontos identificados em revisão e ainda não tratados; são bons candidatos a
contribuição:

- **Markdown com perda** fora do subconjunto (acima). Um modo "preservar
  construções desconhecidas" exigiria um AST em vez de atributos de parágrafo.
- **Diálogos modais no popover**: inserir link (`NSAlert`) e o seletor de
  arquivos (`NSOpenPanel.runModal`) fazem o popover da barra de menu perder o
  foco; funcionam bem na janela destacada. `InlineConfirmation` mostra o padrão
  preferido (confirmação inline).
- **Desfazer** não cobre a inserção de link nem atributos aplicados a parágrafo
  vazio (mutação direta do `textStorage` sem `shouldChangeText`).
- **Sem aviso visual** quando `loadFailed` é verdadeiro (só log + cópia
  `tasks.corrupt-*`). Um banner em `HomeView` resolveria.
- **Desempenho** com milhares de itens: contadores e layout são recalculados a
  cada render e a serialização das notas acontece a cada tecla. Adequado ao uso
  pessoal; cache no store e debounce no editor são os próximos passos.
- **Scheduler sem testes automatizados**: depende de `Timer`, notificações de
  sessão e `NSWindow`; injetar `now` e um protocolo de apresentação permitiria
  testar `check`/`prune`.

## Testes

`Tests/KTaskListTests` cobre: árvore e caminhos (`TaskTreeTests`: profundidade,
limite de níveis, mover, reordenar, validação, rascunhos, exclusão em cascata,
filtros, atraso, persistência e backup, zonas de soltura), layout do mapa
(`MindMapLayoutTests`) e Markdown (`MarkdownConverterTests`,
`MarkdownInputRuleTests`) e persistência (`PersistenceTests`: chaves ausentes,
arquivo ilegível preservado, carregamento sem regravação, flush, sanitização de
anexos, rascunhos × itens reais). Os testes criam um `TaskStore` com
`baseDirectory` temporária e `AppSettings` com `UserDefaults(suiteName:)`
isolado, removido no `tearDown`, sem tocar nos dados reais.
