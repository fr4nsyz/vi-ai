# vi-ai

<img width="1512" height="982" alt="image" src="https://github.com/user-attachments/assets/dccc1055-b69f-4177-b3b8-0038ce848b35" />

Minimal-hint AI tutor for Neovim. You write the code; when stuck, ask. Replies start with the least help that unblocks you and go one level deeper per follow-up.

Backend: `opencode run` (any provider opencode supports). The agent reads the repo with its own read-only tools; the plugin itself only sends the editor context described below.

## What it sends you

Every message you send is prefixed with an `<editor>` block built from your Neovim state at the moment you hit send:

| included | detail |
| --- | --- |
| file | path relative to the repo root, plus filetype |
| cursor | line and column, and the total line count of the file |
| code | the lines around the cursor (default 30 each way), the cursor line marked `>>>` |
| selection | when you asked from visual mode, the selected range replaces the cursor window |
| diagnostics | LSP errors and warnings for the lines in range |
| open buffers | names of your other listed buffers, relative to the repo root |

The code window adapts to the mode: in `tutor` mode it is the code around the cursor; in `design` mode it is the whole buffer (up to 600 lines), because the agent reviews a document rather than a snippet.

You also get a `@ file:line` marker in the chat transcript showing where each question was asked from.

The agent may then read other files in the repo on its own. It is limited to 8 tool calls per reply; when the budget runs out it is told to answer with what it already has.

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
| `<leader>aa` | toggle the panel (opens with the input focused) |
| `<leader>ah` | ask about cursor (normal) or selection (visual) |
| `<leader>ad` | toggle tutor / design mode |
| `<leader>am` | pick model (persisted) |
| `<leader>an` | new session for this repo + mode |
| `<leader>al` | jump to last user message in the chat |

The panel is two windows: the chat transcript on top, the prompt input at the bottom. They are two buffers, because the transcript is a read-only log and the input is an editable prompt; each window keeps its own cursor, so both positions survive while you move between them.

In the input window: any printable key types (the leader key stays a leader key), `<CR>` (normal) or `<C-s>` (insert) sends, `<C-c>` cancels, `<C-k>` goes to the chat. `<C-k>` works while you are typing: the caret position is remembered and `<C-j>` brings you back to it, still in insert mode. Close the panel with `<leader>aa`.

In the chat window: `<C-j>` goes to the input, `<C-c>` cancels, `q` closes.

The panel opens in normal mode with the caret in the input. Scrolling up while a request is streaming keeps your position; the view only auto-follows new output when it is already at the bottom.

`:ViAi [prompt]` opens the chat and optionally sends.

## Modes

- `tutor` (agent `vi-tutor`): hint -> approach -> pseudocode -> one line -> full code. The agent escalates one level per follow-up and never rewrites your code for you.
- `design` (agent `vi-design`): sends the whole buffer; Socratic review of a design doc, at most 3 questions per reply.

Both agents deny `edit` and `bash`.

## Sessions

Each repo root has its own session per mode, keyed as `<repo root>::<mode>`, so switching modes switches conversation. Session IDs are stored in `stdpath("data")/vi-ai.json`.

`<leader>an` drops the stored session for the current repo and mode, so the next message starts a fresh conversation with no memory of the old one. The chat transcript on screen stays as-is; only the backend session is reset.

The selected model is stored in the same file and persists across repos.

## Other providers

`opencode auth login` (e.g. Anthropic), then `<leader>am` and pick the model.
