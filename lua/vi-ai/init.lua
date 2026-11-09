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
  max_tool_calls = 8,
  keys = {
    toggle = "<leader>aa",
    ask = "<leader>ah",
    mode = "<leader>ad",
    model = "<leader>am",
    new = "<leader>an",
  },
}

local st = { mode = "tutor", tool_count = 0, req = 0 }

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

local timer
local started_at
local last_tool

local function elapsed()
  return started_at and (vim.uv.now() - started_at) / 1000 or 0
end

local function shorten(text)
  local s = tostring(text)
  local home = vim.env.HOME
  if home and home ~= "" then
    s = s:gsub(vim.pesc(home), "~")
  end
  if #s > 64 then
    s = s:sub(1, 61) .. "..."
  end
  return s
end

local function tool_arg(input)
  local arg = input.filePath
    or input.path
    or input.pattern
    or input.name
    or input.command
    or input.description
    or input.query
    or input.url
    or input.glob
  if type(arg) == "table" then
    arg = vim.inspect(arg)
  end
  return shorten(arg or "")
end

local function stop_timer()
  if timer then
    timer:stop()
    timer:close()
    timer = nil
  end
end

local function refresh_working()
  local text = string.format("_working… %.0fs_", elapsed())
  if st.tool_count > 0 then
    text = text .. string.format(" _%d tool calls_", st.tool_count)
  end
  if last_tool then
    text = text .. string.format(" _%s_ (%ds ago)", last_tool.text, math.floor(elapsed() - last_tool.at))
  end
  window.set_working(text)
  status(string.format("working %.0fs", elapsed()))
end

local function start_working()
  started_at = vim.uv.now()
  last_tool = nil
  st.tool_count = 0
  st.got_text = false
  window.set_working("_working… 0s_")
  stop_timer()
  timer = vim.uv.new_timer()
  timer:start(1000, 1000, vim.schedule_wrap(refresh_working))
end

local function stop_working()
  stop_timer()
  window.clear_working()
  started_at = nil
  last_tool = nil
end

local function remember_src()
  local w = vim.api.nvim_get_current_win()
  if not window.owns(w) then
    st.src_win = w
  end
end

local run
local wrap_up

local function render(ev)
  local p = ev.part or {}
  if ev.type == "text" then
    st.got_text = true
    local lines = vim.split(p.text or "", "\n")
    lines[#lines + 1] = ""
    window.append(lines)
  elseif ev.type == "tool_use" then
    local state = p.state or {}
    local input = state.input or {}
    local arg = tool_arg(input)
    local name = p.tool or "tool"
    if state.status == "error" then
      local msg = (state.error or {}).message or state.error or "failed"
      local at = arg ~= "" and (" " .. arg) or ""
      window.append({ string.format("**%s failed:**%s %s", name, at, msg), "" })
    else
      window.append({ string.format("_%s %s_", name, arg) })
    end
    last_tool = { text = string.format("%s %s", name, arg), at = elapsed() }
    st.tool_count = st.tool_count + 1
    refresh_working()
    if st.tool_count > M.config.max_tool_calls and not st.wrapping then
      wrap_up()
    end
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
  start_working()

  st.root, st.key = r, k
  st.wrapping = false
  run(prompt, r, k)
end

run = function(prompt, r, k, is_wrap)
  st.req = st.req + 1
  local req = st.req
  st.job = backend.send({
    agent = M.config.agents[st.mode],
    model = model(),
    session = session.get(k),
    cwd = r,
    prompt = prompt,
  }, function(ev)
    if req ~= st.req then
      return
    end
    if ev.sessionID and session.get(k) ~= ev.sessionID then
      session.set(k, ev.sessionID)
    end
    render(ev)
  end, function(code, err)
    if req ~= st.req then
      return
    end
    st.job = nil
    if is_wrap then
      st.wrapping = false
    end
    stop_working()
    if code ~= 0 and err ~= "" then
      window.append({ string.format("**opencode exit %d:** %s", code, err), "" })
    elseif not st.got_text then
      window.append({ "_no answer from the model_", "" })
    end
    status()
  end)
end

wrap_up = function()
  st.wrapping = true
  st.tool_count = 0
  if st.job then
    st.job:kill(15)
    st.job = nil
  end
  window.append({ "_tool budget spent, answering now_", "" })
  run(
    "Tool budget spent. Answer now with what you have already read. No more tool calls. At most 5 sentences.",
    st.root,
    st.key,
    true
  )
end

function M.cancel()
  if st.job then
    st.req = st.req + 1
    st.job:kill(15)
    st.job = nil
    st.wrapping = false
    window.append({ "_cancelled_", "" })
    stop_working()
    session.set(key(), nil)
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
