# KTaskList

Gerenciador de tarefas nativo para **macOS 14+** que vive na **barra de menu** e
organiza os itens como um **mapa mental** (estilo X-Mind). Cada item, em qualquer
nível, tem notas em Markdown, lembrete, anexos e sub-itens. Sem conta, sem nuvem,
sem permissões especiais: os dados ficam em um JSON na sua pasta de usuário.

Projeto open source de [Marcos Khoriati](https://khori.com.br), licença MIT.

```
┌ barra de menu ────────────────────────────────┐
│ ☑ 7                                            │   7 itens pendentes
└────────────────────────────────────────────────┘
   │ clique
   ▼
┌ popover (ou janela destacada) ──────────────────────────────────────┐
│ [Novo item raiz…                               ] (+)   ⋯            │
│ (Pendentes 7) (Concluídas 3) (Atrasadas 1)      Mapa │ Lista        │
│                                                                      │
│  ┌ Projeto X ┐──┬──┌ Levantar requisitos ┐──┌ Entrevistar cliente ┐ │
│  │ 📎2 ⏰    │  │  │ ✓                   │  └──────────────────────┘ │
│  └───────────┘  └──┌ Prototipar tela    ┐                            │
│                    │ atrasado há 2 d     │                            │
│  ┌ Casa ─────┐──┬──└─────────────────────┘                            │
│  └───────────┘  └──┌ Pagar contas ┐                                   │
│                                                                      │
│  1 atrasado(s)                                       −  100 %  +    │
└──────────────────────────────────────────────────────────────────────┘
```

## Sumário

- [Funcionalidades](#funcionalidades)
- [Instalação](#instalação)
- [Uso](#uso)
  - [Mapa mental](#mapa-mental)
  - [Atalhos de teclado](#atalhos-de-teclado)
  - [Notas em Markdown](#notas-em-markdown)
  - [Lembretes](#lembretes)
  - [Anexos](#anexos)
- [Dados e privacidade](#dados-e-privacidade)
- [Desenvolvimento](#desenvolvimento)
- [Documentação complementar](#documentação-complementar)
- [Solução de problemas](#solução-de-problemas)
- [Contribuindo](#contribuindo)
- [Licença](#licença)

## Funcionalidades

- **Barra de menu**: ícone com contador de pendentes; o clique abre o popover.
  O ícone vira um sino enquanto houver alerta de lembrete aberto.
- **Mapa mental** (visão padrão): raízes à esquerda, sub-itens à direita, conectores
  coloridos por árvore. Arrastar-e-soltar move sub-árvores inteiras, reordena
  irmãos e promove itens a raiz. Recolher/expandir por nó, zoom de 50 % a 160 %.
- **Lista (outline)**: visão alternativa com todos os níveis.
- **Filtros rápidos**: Pendentes, Concluídas e Atrasadas, com contadores. Os
  ancestrais dos itens filtrados são mantidos para preservar o caminho.
- **Detalhe do item**: título, notas, lembrete, anexos, sub-itens com barra de
  progresso, trilha de ancestrais e exclusão.
- **Notas em Markdown** com editor WYSIWYG (títulos, ênfase, código, listas,
  citações, links) e regras de digitação no estilo Typora.
- **Lembretes** com horário exato ou "só o dia", em janela própria (não usa as
  notificações do sistema, portanto não pede permissão).
- **Anexos** por seletor de arquivos, arrastar-e-soltar ou colar (imagens).
- **Janela destacada**: o mesmo conteúdo em uma janela normal e redimensionável.
- **Limite de sub-níveis** configurável (padrão 3), iniciar com o login.
- **Local-first**: um único `tasks.json` legível, com backup automático.

## Instalação

Não há binário distribuído na App Store: o app é compilado a partir do código.
São necessários **macOS 14 (Sonoma) ou superior** e as **Command Line Tools do
Xcode** (ou o Xcode 15+).

```bash
xcode-select --install                 # uma vez, se ainda não tiver as ferramentas
git clone https://github.com/khoriati/KTaskList.git
cd KTaskList
scripts/check-env.sh                   # confere macOS, Swift e codesign
scripts/build-app.sh --install         # compila em release e copia para /Applications
open /Applications/KTaskList.app
```

O bundle recebe **assinatura ad-hoc**, suficiente para rodar no próprio Mac. Em
outro Mac o Gatekeeper pode bloquear a primeira abertura; use o clique direito →
**Abrir**, ou compile localmente. O app não aparece no Dock (`LSUIElement`):
procure o ícone ☑ na barra de menu.

Para iniciar com o login, use o menu ⋯ → **Iniciar com o login** (usa
`SMAppService`, sem itens de login manuais).

## Uso

### Mapa mental

| Ação | Como |
|---|---|
| Criar item raiz | Campo "Novo item raiz…" no topo, Enter ou botão + |
| Criar sub-item | Passar o cursor no card → botão **+**; ou selecionar e Tab |
| Criar item irmão | Selecionar e Enter; ou menu de contexto |
| Editar título inline | Enter confirma, Esc cancela; perder o foco confirma |
| Abrir detalhe | Duplo clique; ou selecionar e **O** |
| Concluir / reabrir | Botão ○ no card; ou selecionar e Espaço |
| Recolher / expandir | Botão ao lado direito do card (mostra quantos itens estão ocultos) |
| Mover para dentro de outro | Arrastar o card e soltar no **centro** do destino |
| Reordenar / mudar de pai | Arrastar e soltar na **borda superior ou inferior** de outro card |
| Tornar raiz | Arrastar e soltar no fundo do mapa |
| Mover sem arrastar | Menu de contexto → Mover para… / Mover para cima / para baixo |
| Zoom | Controles − / + no rodapé |

Cores durante o arrasto indicam se a soltura é válida. Soltar um item dentro de
si mesmo ou além do limite de níveis é recusado com um aviso.

### Atalhos de teclado

Com um card selecionado no mapa:

| Tecla | Ação |
|---|---|
| Tab | Novo sub-item |
| Enter | Novo item irmão |
| Espaço | Concluir / reabrir |
| O | Abrir detalhe |
| ⌫ / Delete | Excluir (pede confirmação) |
| Esc | Limpar seleção |

No editor de notas: ⌘B negrito, ⌘I itálico, ⌘E código inline, ⌘⇧X tachado.
Configurações: ⌘, (ou menu ⋯).

### Notas em Markdown

O texto é **salvo como Markdown** no JSON e **editado já renderizado**. Colar um
texto Markdown converte na hora. Regras de digitação:

| Digitar no início da linha | Resultado |
|---|---|
| `# `, `## `, `### ` | Título 1, 2, 3 |
| `- ` ou `* ` | Lista com marcador |
| `1. ` | Lista numerada |
| `> ` | Citação |
| ```` ``` ```` | Bloco de código (Enter em linha vazia sai do bloco) |
| `**texto**`, `*texto*`, `` `texto` ``, `~~texto~~` | Aplica o estilo ao fechar o marcador |

Enter em um item de lista vazio encerra a lista. O subconjunto suportado está
descrito em [docs/arquitetura.md](docs/arquitetura.md#markdown).

### Lembretes

Cada item pode ter um lembrete, definido na tela de detalhe:

- **Com horário**: o alerta abre na data/hora exata (verificação a cada 20 s).
  Lembretes perdidos com o Mac dormindo aparecem ao acordar ou desbloquear.
- **Só o dia**: o alerta abre quando você faz login, desbloqueia a tela, o Mac
  acorda ou o app é aberto naquele dia (ou depois, se perdido).

A janela de alerta lista os lembretes vencidos com **Abrir**, **Adiar**
(10 min / 1 h / 3 h / amanhã 09:00), **Concluir** e **OK**. OK (ou fechar a
janela) só esconde até a próxima oportunidade: enquanto a tarefa não for concluída
ou o lembrete removido, ele volta a cada login, desbloqueio, wake ou abertura do
app. Um item com prazo vencido aparece como **atrasado** (vermelho, com "há quanto
tempo") mesmo depois de dispensar o alerta.

Para o lembrete "só o dia" funcionar no login, ative **Iniciar com o login**.

### Anexos

Na tela de detalhe: seletor de arquivos, arrastar do Finder (ou imagens de
qualquer app) ou colar (⌘V) uma imagem. O arquivo é **copiado** para a pasta de
anexos do app; o original não é tocado. Duplo clique abre com o app padrão; o
menu de contexto mostra no Finder ou remove a cópia.

## Dados e privacidade

Tudo fica em `~/Library/Application Support/KTaskList/`:

| Arquivo | Conteúdo |
|---|---|
| `tasks.json` | Árvore completa de itens (`subtasks` recursivo), gravada de forma atômica com debounce de 300 ms |
| `tasks.backup.json` | Cópia do último arquivo carregado com sucesso, feita a cada abertura |
| `Attachments/` | Cópias dos anexos, nomeadas `<uuid>.<extensão>` |

Preferências (limite de níveis, visão, zoom, filtros, nós recolhidos) ficam em
`UserDefaults` (`defaults read br.com.khori.ktasklist`).

O app não acessa a rede, não coleta telemetria e não pede permissões. O formato do
JSON está documentado em [docs/formato-de-dados.md](docs/formato-de-dados.md);
ele pode ser editado à mão com o app fechado, ou gerado por outras ferramentas.

Quem usava a versão anterior (pasta `TaskList` contendo um `tasks.json`) é
migrado automaticamente na primeira abertura: a pasta é renomeada para `KTaskList`.

Variáveis de ambiente úteis em desenvolvimento:

| Variável | Efeito |
|---|---|
| `KTASKLIST_DATA_DIR=/outra/pasta` | Usa outra pasta de dados (isola testes manuais) |
| `KTASKLIST_OPEN_WINDOW=1` | Abre a janela destacada logo no início |
| `KTASKLIST_OPEN_WINDOW=<uuid>` | Abre direto no detalhe do item indicado |

## Desenvolvimento

Swift Package puro (sem `.xcodeproj`); compila com `swift build` ou abre no Xcode
via `Package.swift`. Dependências externas: nenhuma.

```bash
scripts/check-env.sh             # pré-requisitos
swift build                      # debug
swift test                       # 35 testes XCTest (árvore, movimentação, persistência, layout, Markdown)
swift run KTaskList              # executa o binário debug (ícone aparece na barra de menu)
scripts/build-app.sh             # release + bundle em dist/KTaskList.app
scripts/build-app.sh --install   # idem e copia para /Applications
```

Para testar sem mexer nos seus dados reais:

```bash
KTASKLIST_DATA_DIR=/tmp/ktl KTASKLIST_OPEN_WINDOW=1 swift run KTaskList
```

Ícone opcional: coloque `Resources/AppIcon.icns` antes de rodar o script de build.

Estrutura resumida (detalhes em [docs/arquitetura.md](docs/arquitetura.md)):

```
Package.swift                 targets KTaskList (executável) e KTaskListTests
Sources/KTaskList/
  KTaskListApp.swift          cenas: MenuBarExtra, Window destacada, Settings; rotas
  Models.swift                TaskItem (árvore), Attachment, Reminder, operações por caminho
  TaskStore.swift             fonte da verdade: persistência JSON, anexos, mover/reordenar
  AppSettings.swift           preferências em UserDefaults
  MindMapLayout.swift         layout puro do mapa (posições e conectores)
  MarkdownConverter.swift     Markdown ⇄ NSAttributedString
  ReminderScheduler.swift     disparo de lembretes, janela de alerta, janelas destacadas
  Views/                      HomeView, MindMapCanvasView, TaskCardView, TaskOutlineView,
                              TaskDetailView, MarkdownEditor, AttachmentsSection,
                              ReminderAlertView, SettingsView, InlineConfirmation
Tests/KTaskListTests/         XCTest
Resources/Info.plist          LSUIElement, bundle id br.com.khori.ktasklist
scripts/                      check-env.sh, build-app.sh
docs/                         arquitetura, formato de dados
```

## Documentação complementar

| Documento | Para quem |
|---|---|
| [docs/arquitetura.md](docs/arquitetura.md) | Quem vai alterar o código: camadas, fluxo de dados, decisões e pontos de extensão |
| [docs/formato-de-dados.md](docs/formato-de-dados.md) | Quem vai ler/gerar `tasks.json` por fora ou migrar dados |
| [CONTRIBUTING.md](CONTRIBUTING.md) | Como abrir issues e PRs, padrão de commits e testes |
| [AGENTS.md](AGENTS.md) | Instruções para agentes de IA (build, testes, convenções) |
| [CHANGELOG.md](CHANGELOG.md) | Histórico de versões |

## Solução de problemas

**O ícone não aparece na barra de menu.** A barra pode estar cheia (o macOS oculta
ícones à esquerda do notch). Feche outros itens ou use a janela destacada
(`KTASKLIST_OPEN_WINDOW=1`). Confira também se o processo está rodando:
`pgrep -x KTaskList`.

**Não consigo digitar no título de um sub-item novo.** O app é "accessory"
(sem Dock) e, em alguns macOS, o painel da barra de menu não ativava o app; o
campo agora força a ativação e insiste no foco. Se ainda ocorrer, clique uma vez
dentro do campo. Abra uma issue informando a versão do macOS.

**"KTaskList não pode ser aberto porque é de um desenvolvedor não identificado".**
Assinatura ad-hoc em outro Mac. Clique direito → Abrir, ou compile localmente
com `scripts/build-app.sh --install`.

**O app abriu vazio e meus itens sumiram.** O `tasks.json` não pôde ser lido. O
arquivo original foi preservado como `tasks.corrupt-<data>.json` na mesma pasta;
há também `tasks.backup.json` (último arquivo carregado com sucesso). Com o app
fechado, corrija o JSON (ou restaure o backup) renomeando-o para `tasks.json`.
O log diz o motivo:
`log show --last 1h --predicate 'subsystem == "br.com.khori.ktasklist"'`.

**Lembrete "só o dia" não apareceu no login.** Ative "Iniciar com o login" no
menu ⋯; sem o app rodando não há quem dispare o alerta.

**Build falha com erro de versão do Swift.** Exige Swift 5.9+ (Xcode 15+). Rode
`scripts/check-env.sh`.

## Contribuindo

Issues e pull requests são bem-vindos. Leia o [CONTRIBUTING.md](CONTRIBUTING.md):
Conventional Commits em português, `swift test` verde e descrição do
comportamento alterado.

## Licença

[MIT](LICENSE) © 2026 Marcos Khoriati.
