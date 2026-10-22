# CLAUDE.md

As instruções deste repositório para agentes de IA estão em [AGENTS.md](AGENTS.md).
Leia-o integralmente antes de compilar, testar ou alterar código. Resumo:

- `scripts/check-env.sh` → `swift build` → `swift test` (35 testes devem passar).
- Rodar isolado: `KTASKLIST_DATA_DIR=/tmp/ktl KTASKLIST_OPEN_WINDOW=1 swift run KTaskList`.
- Instalar: `scripts/build-app.sh --install`.
- Código, comentários, commits e docs em português (Brasil); Conventional Commits; sem
  trailers de co-autoria.
