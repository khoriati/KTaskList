# Formato de dados (`tasks.json`)

Arquivo: `~/Library/Application Support/KTaskList/tasks.json`
(ou `$KTASKLIST_DATA_DIR/tasks.json`). Codificado por `JSONEncoder` com
`dateEncodingStrategy = .iso8601`, `prettyPrinted` e `sortedKeys`; lido por
`JSONDecoder` com `.iso8601`. Gravação atômica; `tasks.backup.json` é a cópia do
último arquivo carregado com sucesso.

## Estrutura

A raiz é um **array** de itens. Cada item tem a mesma forma em qualquer nível.

```json
[
  {
    "attachments": [
      {
        "createdAt": "2026-10-20T13:05:12Z",
        "displayName": "briefing.pdf",
        "fileName": "6F1C2A3B-9D41-4E7A-8C55-0B2E7D1A9F10.pdf",
        "id": "6F1C2A3B-9D41-4E7A-8C55-0B2E7D1A9F10"
      }
    ],
    "createdAt": "2026-10-20T12:58:40Z",
    "id": "2B7E4C0D-1F3A-4D5E-9A8B-7C6D5E4F3A2B",
    "isDone": false,
    "notes": "## Contexto\n\nReunião em **2026-10-24**.\n\n- [ ] enviar proposta",
    "reminder": {
      "acknowledgedAt": "2026-10-21T09:00:03Z",
      "date": "2026-10-21T00:00:00Z",
      "hasTime": false
    },
    "subtasks": [
      {
        "attachments": [],
        "createdAt": "2026-10-20T13:00:00Z",
        "id": "9C8B7A6F-5E4D-4C3B-A2F1-0E9D8C7B6A5F",
        "isDone": true,
        "notes": "",
        "subtasks": [],
        "title": "Entrevistar cliente"
      }
    ],
    "title": "Levantar requisitos"
  }
]
```

### `TaskItem`

| Campo | Tipo | Obrigatório | Padrão | Descrição |
|---|---|---|---|---|
| `id` | UUID (string) | não | novo UUID | Identificador estável; usado em rotas, nós recolhidos e drag-and-drop |
| `title` | string | **sim** | — | Título; vazio só existe transitoriamente (rascunho em edição) |
| `notes` | string | não | `""` | Markdown (subconjunto descrito em [arquitetura.md](arquitetura.md#editor-de-notas-markdown-wysiwyg)) |
| `isDone` | bool | não | `false` | Concluído |
| `createdAt` | data ISO 8601 | não | agora | Criação |
| `attachments` | `[Attachment]` | não | `[]` | Anexos do próprio item |
| `subtasks` | `[TaskItem]` | não | `[]` | Sub-itens, recursivo; a ordem é a ordem de exibição |
| `reminder` | `Reminder` | não | ausente | Lembrete / data planejada. Ausente quando `nil` |

### `Attachment`

| Campo | Tipo | Obrigatório | Descrição |
|---|---|---|---|
| `id` | UUID | não | Identificador |
| `fileName` | string | **sim** | Nome físico em `Attachments/` (`<uuid>.<ext>`) |
| `displayName` | string | **sim** | Nome mostrado ao usuário (original) |
| `createdAt` | data | não | Quando foi anexado |

O arquivo em `Attachments/` não é referenciado por caminho absoluto: a pasta pode
ser movida junto com o JSON.

### `Reminder`

| Campo | Tipo | Obrigatório | Descrição |
|---|---|---|---|
| `date` | data | **sim** | Instante planejado (UTC no arquivo; o app converte para o fuso local) |
| `hasTime` | bool | **sim** | `true`: alerta na hora exata; `false`: lembrete "só o dia" |
| `acknowledgedAt` | data | não | Quando o alerta foi dispensado; ausente = pendente |

Semântica derivada (não gravada): `fireDate` (hora exata ou início do dia),
`deadline` (hora exata ou fim do dia), `isDue` (pendente e vencido),
`isLate` (prazo passado, independentemente de dispensa).

## Regras de compatibilidade

- Só `title` (item), `fileName` (anexo) e `date` (lembrete) são obrigatórios. Os
  demais campos são **opcionais na leitura** e assumem o padrão da tabela
  (`init(from:)` manual em `Models.swift`); arquivos antigos ou gerados por fora
  carregam normalmente.
- Campos desconhecidos são **ignorados** na leitura e **perdidos** na próxima
  gravação (o `Codable` sintetizado não os preserva). Ferramentas externas não
  devem guardar metadados próprios dentro de `tasks.json`.
- `id` duplicado não é validado; gere UUIDs únicos ao criar itens por fora.
- Datas devem estar em ISO 8601 com `Z` ou offset; sem isso o arquivo inteiro
  falha a decodificar. Nesse caso o app copia o arquivo para
  `tasks.corrupt-<data>.json`, loga o erro e inicia vazio; a próxima alteração
  grava um `tasks.json` novo, mas a cópia e o `tasks.backup.json` permanecem.
- `fileName` de anexo é reduzido ao último componente do caminho ao resolver o
  arquivo: não é possível referenciar nada fora de `Attachments/`.

## Editar ou gerar por fora

1. Encerre o app (`pkill -x KTaskList`) para evitar que uma gravação com debounce
   sobrescreva sua edição.
2. Edite `tasks.json` (ou gere a partir de outra fonte seguindo a estrutura acima).
3. Valide: `python3 -m json.tool tasks.json > /dev/null`.
4. Abra o app. Se algo falhar, veja `tasks.backup.json` e o log:
   `log show --last 10m --predicate 'subsystem == "br.com.khori.ktasklist"'`.

## Preferências (`UserDefaults`)

Domínio `br.com.khori.ktasklist` (`defaults read br.com.khori.ktasklist`):

| Chave | Tipo | Padrão |
|---|---|---|
| `maxSubLevels` | int (1–6) | 3 |
| `showCompleted`, `showPending` | bool | true |
| `onlyLate` | bool | false |
| `viewMode` | `map` ou `list` | `map` |
| `mapZoom` | double (0.5–1.6) | 1 |
| `collapsedIDs` | array de UUID | vazio |
