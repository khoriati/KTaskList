# Contribuindo com o KTaskList

Obrigado pelo interesse. Este guia explica como propor mudanças de forma que
sejam fáceis de revisar e integrar.

## Antes de começar

- Procure uma issue existente sobre o tema. Para mudanças grandes (novo tipo de
  visão, mudança no formato de dados, dependência externa), abra uma issue
  primeiro para alinhar a abordagem.
- Leia [docs/arquitetura.md](docs/arquitetura.md): explica as camadas e as decisões
  que não devem ser revertidas sem discussão (JSON local, janela de alerta própria,
  `TaskStore` como única fonte da verdade).

## Ambiente

macOS 14+ e Swift 5.9+ (Xcode 15+ ou Command Line Tools). Rode
`scripts/check-env.sh` e depois:

```bash
swift build && swift test
```

Para testar a interface sem tocar nos seus dados:

```bash
KTASKLIST_DATA_DIR=/tmp/ktl KTASKLIST_OPEN_WINDOW=1 swift run KTaskList
```

## Padrões

- **Idioma**: código e identificadores em inglês; comentários, docs, strings de
  interface e commits em português (Brasil).
- **Estilo**: 4 espaços, `// MARK:` para seções, doc comments `///` nas APIs
  públicas de cada tipo. Sem dependências externas.
- **Arquitetura**: lógica pura (árvore, layout, Markdown) fora das views e coberta
  por testes; views só chamam métodos de `TaskStore`/`AppSettings`.
- **Formato de dados**: campos novos em `TaskItem`, `Reminder` ou `Attachment`
  precisam de valor padrão para que arquivos antigos continuem carregando. Ao
  mudar o formato, atualize [docs/formato-de-dados.md](docs/formato-de-dados.md).

## Testes

- `swift test` deve passar. Adicione testes em `Tests/KTaskListTests` para
  qualquer regra de negócio nova (movimentação, filtro, layout, conversão).
- Mudanças de interface: descreva no PR o que foi testado manualmente, no
  popover da barra de menu **e** na janela destacada.

## Commits e pull requests

- [Conventional Commits](https://www.conventionalcommits.org/pt-br/) em
  português, imperativo, assunto com até 72 caracteres:
  `feat(lembretes): permitir adiar por 1 dia`, `fix(mapa): …`, `docs: …`,
  `refactor(store): …`, `test(layout): …`.
- Um commit por bloco lógico; sem trailers de co-autoria ou rodapés de ferramentas.
- No PR: o quê e por quê, como testar, capturas de tela quando houver mudança
  visual, e a entrada correspondente em `CHANGELOG.md` ("Não lançado").

## Reportando bugs

Inclua a versão do macOS (`sw_vers`), se ocorreu no popover ou na janela
destacada, passos para reproduzir e, se possível, um `tasks.json` mínimo que
reproduza o problema (sem dados pessoais).
