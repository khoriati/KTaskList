# Changelog

Formato baseado em [Keep a Changelog](https://keepachangelog.com/pt-BR/1.1.0/);
versões seguem [SemVer](https://semver.org/lang/pt-BR/).

## Não lançado

## 1.0.0 — 2026-10-22

Primeira versão pública, publicada como **KTaskList** (antes chamada TaskList).

### Adicionado
- App de barra de menu com contador de pendentes e popover.
- Mapa mental com cards, conectores coloridos por árvore, hover com + e
  recolher/expandir, arrastar-e-soltar (mover para dentro, reordenar, promover a
  raiz), zoom e atalhos de teclado.
- Visão em lista (outline), filtros rápidos (Pendentes, Concluídas, Atrasadas).
- Detalhe do item com notas em Markdown (editor WYSIWYG com regras de digitação),
  lembretes, anexos e sub-itens.
- Lembretes com horário ou "só o dia", janela de alerta própria com adiar,
  concluir e abrir; re-exibição em login, desbloqueio e wake.
- Janela destacada, limite de sub-níveis configurável, iniciar com o login.
- Persistência em `tasks.json` com gravação atômica e backup automático.
- `scripts/check-env.sh` para verificar pré-requisitos; `AGENTS.md`, docs de
  arquitetura e de formato de dados; CI com `swift build` e `swift test`.

### Alterado
- Renomeado para KTaskList: bundle `br.com.khori.ktasklist`, pasta de dados
  `~/Library/Application Support/KTaskList/` (migrada automaticamente da antiga
  `TaskList/`), variáveis `KTASKLIST_DATA_DIR` e `KTASKLIST_OPEN_WINDOW`.

### Corrigido
- Editor inline de sub-item sem receber teclado em alguns Macs: o campo agora
  ativa o app, insiste no foco em várias tentativas e ignora perda de foco antes
  de tê-lo recebido; clicar no card em edição não devolve o foco ao canvas.
- Alteração feita até 300 ms antes de Sair/logout podia não ser gravada: o
  debounce é descarregado em `willTerminate`.
- Apagar o título de um item real (no detalhe ou inline) removia o item com
  sub-itens e anexos; agora só rascunhos não confirmados são removidos e o
  título anterior é restaurado.
- `tasks.json` sem algum campo opcional (`id`, `notes`, `createdAt`…) falhava
  inteiro; a leitura passou a ser tolerante e, em falha real, o arquivo é
  preservado em `tasks.corrupt-<data>.json`.
- A migração da pasta antiga só ocorre se houver `TaskList/tasks.json`, para não
  mover a pasta de outro app com o mesmo nome.
- Carregar o arquivo não agenda mais uma regravação idêntica a cada abertura.
- Arrasto cancelado deixava o card semitransparente e um alvo "fantasma".
- Timer dos lembretes passou ao modo `.common` (dispara com menus abertos);
  observers removidos no `deinit`; fechamento da janela de alerta sem reentrância.
- Links nas notas limitados a `http`, `https` e `mailto`; nome de arquivo de
  anexo sanitizado; atalhos do editor funcionam com Caps Lock ligado.
- Formatadores de data em cache e com locale fixo (`en_US_POSIX`).
- Testes não deixam mais `.plist` em `~/Library/Preferences`; novos testes de
  persistência e de rascunhos.
