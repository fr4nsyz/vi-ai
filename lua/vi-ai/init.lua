local backend = require("vi-ai.backend")
local context = require("vi-ai.context")
local session = require("vi-ai.session")
local window = require("vi-ai.window")

local M = {}

M.config = {
  model = nil,
  agents = { tutor = "vi-tutor", design = "vi-design" },
  radius = 30,
  max_doc_lines = 600,
  width = 70,
  keys = {
    toggle = "<leader>aa",
    ask = "<leader>ah",
    mode = "<leader>ad",
    model = "<leader>am",
    new = "<leader>an",
  },
}

local st = { mode = "tutor" }

local function src_ok()
  return st.src_win and vim.api.nvim_win_is_valid(st.src_win)
end

local function root()
  local buf = src_ok() and vim.api.nvim_win_get_buf(st.src_win) or 0
  return vim.fs.root(buf, ".git") or vim.fn.getcwd()
end

local function key()
  return root() .. "::" .. st.mode
end

local function model()
  return session.model() or M.config.model
end

local function status(extra)
  local text = string.format(" vi-ai  %s  %s", st.mode, model() or "opencode default")
  window.set_status(extra and (text .. "  " .. extra) or text)
end

local function remember_src()
  local w = vim.api.nvim_get_current_win()
  if not window.owns(w) then
    st.src_win = w
  end
end

local function render(ev)
  local p = ev.part or {}
  if ev.type == "text" then
    local lines = vim.split(p.text or "", "\n")
    lines[#lines + 1] = ""
    window.append(lines)
  elseif ev.type == "tool_use" then
    local input = (p.state or {}).input or {}
    window.append({ string.format("_%s %s_", p.tool, input.path or input.filePath or input.pattern or "") })
  elseif ev.type == "error" then
    window.append({ "**error:** " .. ((ev.error or {}).message or vim.inspect(ev)), "" })
  end
end

function M.submit()
  local text = window.take_input()
  if text == "" then
    return
  end
  if st.job then
    vim.notify("vi-ai: request running, <C-c> to cancel", vim.log.levels.WARN)
    window.set_input(text)
    return
  end

  local r, k = root(), key()
  local prompt = text
  local where = ""
  if src_ok() then
    prompt = string.format(
      "<editor>\n%s\n</editor>\n\n%s",
      context.build(st.src_win, {
        root = r,
        whole = st.mode == "design",
        radius = M.config.radius,
        max_lines = M.config.max_doc_lines,
        selection = st.selection,
      }),
      text
    )
    local buf = vim.api.nvim_win_get_buf(st.src_win)
    where = string.format(
      "_@ %s:%d_",
      vim.fn.fnamemodify(vim.api.nvim_buf_get_name(buf), ":t"),
      vim.api.nvim_win_get_cursor(st.src_win)[1]
    )
  end
  st.selection = nil

  local lines = { "## You " .. where, "" }
  vim.list_extend(lines, vim.split(text, "\n"))
  vim.list_extend(lines, { "", "## AI", "" })
  window.append(lines)
  status("working...")

  st.job = backend.send({
    agent = M.config.agents[st.mode],
    model = model(),
    session = session.get(k),
    cwd = r,
    prompt = prompt,
  }, function(ev)
    if ev.sessionID and session.get(k) ~= ev.sessionID then
      session.set(k, ev.sessionID)
    end
    render(ev)
  end, function(code, err)
    st.job = nil
    if code ~= 0 and err ~= "" then
      window.append({ string.format("**opencode exit %d:** %s", code, err), "" })
    end
    status()
  end)
end

function M.cancel()
  if st.job then
    st.job:kill(15)
    st.job = nil
    window.append({ "_cancelled_", "" })
    status()
  end
end

function M.toggle()
  if window.is_open() then
    window.close()
    return
  end
  remember_src()
  window.open()
  status()
  window.focus_input(true)
end

---@param visual boolean
function M.ask(visual)
  remember_src()
  if visual then
    local a, b = vim.fn.line("v"), vim.fn.line(".")
    st.selection = { math.min(a, b), math.max(a, b) }
    vim.api.nvim_feedkeys(vim.keycode("<Esc>"), "nx", false)
  end
  window.open()
  status()
  window.focus_input(true)
end

function M.toggle_mode()
  st.mode = st.mode == "tutor" and "design" or "tutor"
  window.append({ "---", "_mode: " .. st.mode .. "_", "" })
  status()
end

function M.pick_model()
  backend.models(function(list)
    vim.ui.select(list, { prompt = "vi-ai model" }, function(choice)
      if choice then
        session.set_model(choice)
        status()
      end
    end)
  end)
end

function M.new_session()
  session.set(key(), nil)
  window.append({ "---", "_new " .. st.mode .. " session_", "" })
end

function M.setup(opts)
  M.config = vim.tbl_deep_extend("force", M.config, opts or {})
  window.setup({ submit = M.submit, cancel = M.cancel, width = M.config.width })

  local k = M.config.keys
  vim.keymap.set("n", k.toggle, M.toggle, { desc = "vi-ai: toggle chat" })
  vim.keymap.set("n", k.ask, function()
    M.ask(false)
  end, { desc = "vi-ai: ask about cursor" })
  vim.keymap.set("x", k.ask, function()
    M.ask(true)
  end, { desc = "vi-ai: ask about selection" })
  vim.keymap.set("n", k.mode, M.toggle_mode, { desc = "vi-ai: toggle tutor/design" })
  vim.keymap.set("n", k.model, M.pick_model, { desc = "vi-ai: pick model" })
  vim.keymap.set("n", k.new, M.new_session, { desc = "vi-ai: new session" })

  vim.api.nvim_create_user_command("ViAi", function(cmd)
    remember_src()
    window.open()
    status()
    if cmd.args ~= "" then
      window.set_input(cmd.args)
      M.submit()
    end
  end, { nargs = "*", desc = "vi-ai: open chat, optionally send a prompt" })
end

return M
