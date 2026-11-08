# vi-ai

Minimal-hint AI tutor for Neovim. You write the code; when stuck, ask. Replies start with the least help that unblocks you and go one level deeper per follow-up.

Backend: `opencode run` (any provider opencode supports). Context sent per message: file, cursor, code around cursor or selection, diagnostics, open buffer names. The agent reads the rest of the repo with its own read-only tools.

## Install

```sh
ln -sf ~/Documents/vi-ai/agents/vi-tutor.md ~/.config/opencode/agent/vi-tutor.md
ln -sf ~/Documents/vi-ai/agents/vi-design.md ~/.config/opencode/agent/vi-design.md
```

lazy.nvim:

```lua
{ dir = "~/Documents/vi-ai", opts = { model = "opencode/big-pickle" } }
```

## Keys

| key | action |
| --- | --- |
| `<leader>aa` | toggle chat |
| `<leader>ah` | ask about cursor (normal) or selection (visual) |
| `<leader>ad` | toggle tutor / design mode |
| `<leader>am` | pick model (persisted) |
| `<leader>an` | new session for this repo + mode |

In the input window: `<CR>` (normal) or `<C-s>` (insert) sends, `<C-c>` cancels, `q` closes.

`:ViAi [prompt]` opens the chat and optionally sends.

## Modes

- `tutor` (agent `vi-tutor`): hint -> approach -> pseudocode -> one line -> full code.
- `design` (agent `vi-design`): sends the whole buffer; Socratic review of a design doc.

Both agents deny `edit` and `bash`. Sessions are per repo root + mode, stored in `stdpath("data")/vi-ai.json`.

## Other providers

`opencode auth login` (e.g. Anthropic), then `<leader>am` and pick the model.
