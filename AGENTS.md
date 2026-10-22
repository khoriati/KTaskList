# Instruções para agentes de IA

Este arquivo orienta qualquer assistente de código (Claude Code, Codex, Copilot,
Cursor, Gemini CLI…) que trabalhe neste repositório. `CLAUDE.md` apenas aponta
para cá. Leia também o [README](README.md) e [docs/arquitetura.md](docs/arquitetura.md)
antes de alterar código.

## O que é o projeto

KTaskList: app nativo macOS 14+ de barra de menu (SwiftUI + AppKit), Swift Package
puro, sem dependências externas, sem `.xcodeproj`. Tarefas em árvore recursiva,
persistidas em JSON local. Idioma do código, comentários, commits e docs:
**português (Brasil)**; nomes de tipos e funções em inglês, como já está.

## Pré-requisitos e preparação (faça nesta ordem)

1. Confirme que está em **macOS 14+** com **Swift 5.9+**. Rode:
   ```bash
   scripts/check-env.sh
   ```
   O script diz exatamente o que falta e como instalar. Caso típico:
   ```bash
   xcode-select --install        # Command Line Tools (inclui swift e codesign)
   sudo xcodebuild -license accept   # só se o Xcode completo estiver instalado e pedir aceite
   ```
2. Não há `pnpm install`, `pod install` nem SPM resolve: `swift build` já baixa
   tudo (não há pacotes externos).
3. Se o ambiente **não for macOS**, não tente compilar: diga ao usuário que o
   projeto só compila em macOS e limite-se a alterações revisáveis (docs, lógica
   pura em `Models.swift`, `MindMapLayout.swift`, `MarkdownConverter.swift`),
   deixando claro que não foram testadas.

## Comandos canônicos

| Objetivo | Comando | Observação |
|---|---|---|
| Compilar (debug) | `swift build` | ~15 s na primeira vez |
| Testes | `swift test` | 35 testes XCTest; devem passar sempre |
| Um teste só | `swift test --filter TaskTreeTests/testMoveValidation` | `Classe/método` |
| Rodar sem instalar | `KTASKLIST_DATA_DIR=/tmp/ktl KTASKLIST_OPEN_WINDOW=1 swift run KTaskList` | isola os dados e abre a janela |
| Bundle release | `scripts/build-app.sh` | gera `dist/KTaskList.app` com assinatura ad-hoc |
| Instalar | `scripts/build-app.sh --install` | fecha a instância, copia para `/Applications` |
| Encerrar o app | `osascript -e 'tell application "KTaskList" to quit'` ou `pkill -x KTaskList` | |
| Limpar build | `rm -rf .build dist` | |

Não existe lint configurado. Mantenha o estilo do código vizinho (4 espaços,
`// MARK:`, doc comments `///` em português).

## Regras ao alterar código

- **Nunca quebre o formato de `tasks.json`** sem migração: ele é lido por
  `TaskStore.load()` com `JSONDecoder` e datas ISO 8601. Campos novos devem ter
  valor padrão **e** entrar no `init(from:)` manual com `decodeIfPresent` em
  `Models.swift` (o `Codable` sintetizado exige todas as chaves). Veja
  [docs/formato-de-dados.md](docs/formato-de-dados.md).
- **`TaskStore` é a única fonte da verdade** e é `@MainActor`. Views mudam dados
  só por métodos do store (`update`, `move`, `commitTitle`…), nunca mutando
  cópias de `TaskItem`. Remoção por título vazio só vale para rascunhos
  (`draftIDs`); nunca apague um item real sem confirmação do usuário.
- Lógica pura (árvore, layout, Markdown) vai nos módulos sem UI e **ganha teste**
  em `Tests/KTaskListTests`. Views SwiftUI não têm testes automatizados; valide
  manualmente com `swift run` e descreva o que foi verificado.
- Lembretes: não use `UNUserNotificationCenter` (exige bundle assinado e permissão).
  A janela de alerta própria é decisão de projeto.
- O app é `LSUIElement` (sem Dock). Campos de texto no popover da barra de menu
  precisam que o app esteja ativo (`NSApp.activate`), já tratado em
  `KTaskListApp` e `InlineTitleEditor`; preserve isso.
- Strings de UI em português, datas no formato ISO `YYYY-MM-DD`.
- Não introduza dependências externas sem necessidade clara e sem discutir na PR.

## Fluxo de entrega

1. Branch a partir de `main` (`feat/…`, `fix/…`, `docs/…`).
2. `swift build && swift test` verdes.
3. Se mexeu em UI: `scripts/build-app.sh --install` e teste no popover **e** na
   janela destacada.
4. Commit em **Conventional Commits em pt-BR**, imperativo, ≤ 72 caracteres:
   `fix(mapa): garantir foco no editor inline de sub-item`. Um commit por bloco
   lógico. Sem trailers de co-autoria ou assinatura de ferramenta.
5. Atualize `CHANGELOG.md` (seção "Não lançado") e a documentação afetada
   (README, docs/) no mesmo PR.

## Onde está cada coisa

| Quero… | Arquivo |
|---|---|
| Mudar o modelo / regras da árvore | `Sources/KTaskList/Models.swift` |
| Persistência, anexos, mover/reordenar | `Sources/KTaskList/TaskStore.swift` |
| Preferências | `Sources/KTaskList/AppSettings.swift` |
| Posições e conectores do mapa | `Sources/KTaskList/MindMapLayout.swift` |
| Cards, hover, drag-and-drop, teclado do mapa | `Views/MindMapCanvasView.swift`, `Views/TaskCardView.swift` |
| Editor de notas | `Views/MarkdownEditor.swift`, `MarkdownConverter.swift` |
| Lembretes e janelas | `ReminderScheduler.swift`, `Views/ReminderAlertView.swift` |
| Cabeçalho, filtros, rodapé, menu ⋯ | `Views/HomeView.swift` |
| Detalhe do item | `Views/TaskDetailView.swift`, `Views/AttachmentsSection.swift` |
| Cenas e rotas | `KTaskListApp.swift` |
