local M = {}

local s = { user_lines = {}, input_cursor = nil, input_insert = false }

local function buf_ok(b)
  return b and vim.api.nvim_buf_is_valid(b)
end

local function win_ok(w)
  return w and vim.api.nvim_win_is_valid(w)
end

local function scratch(name)
  local b = vim.api.nvim_create_buf(false, true)
  vim.bo[b].bufhidden = "hide"
  vim.bo[b].filetype = "markdown"
  vim.api.nvim_buf_set_name(b, name)
  return b
end

local function style(win)
  vim.wo[win].wrap = true
  vim.wo[win].linebreak = true
  vim.wo[win].number = false
  vim.wo[win].relativenumber = false
  vim.wo[win].signcolumn = "no"
  vim.wo[win].winfixwidth = true
end

local function map(buf, modes, lhs, fn)
  vim.keymap.set(modes, lhs, fn, { buffer = buf, nowait = true, silent = true })
end

---True while the editor is in an insert-like mode.
---@return boolean
local function in_insert()
  local mode = vim.api.nvim_get_mode().mode
  return mode:sub(1, 1) == "i" or mode:sub(1, 1) == "R"
end

---Remember the input caret and the mode we left it in.
local function save_input()
  if not win_ok(s.iwin) then
    return
  end
  local cur = vim.api.nvim_win_get_cursor(s.iwin)
  s.input_cursor = { cur[1], cur[2] }
  s.input_insert = in_insert()
end

---Put the input caret back where it was.
---@param insert? boolean nil keeps the mode we left the input in
---@return boolean restored
local function restore_input(insert)
  if not (win_ok(s.iwin) and buf_ok(s.ibuf)) or not s.input_cursor then
    return false
  end
  local count = vim.api.nvim_buf_line_count(s.ibuf)
  local line = math.min(math.max(s.input_cursor[1], 1), count)
  local text = vim.api.nvim_buf_get_lines(s.ibuf, line - 1, line, false)[1] or ""
  local len = #text
  local col = math.min(s.input_cursor[2], len)
  local want_insert = s.input_insert
  if insert ~= nil then
    want_insert = insert
  end
  if not want_insert then
    vim.api.nvim_win_set_cursor(s.iwin, { line, math.min(col, math.max(len - 1, 0)) })
    return true
  end
  if col >= len then
    vim.api.nvim_win_set_cursor(s.iwin, { line, math.max(len - 1, 0) })
    vim.cmd("startinsert!")
  else
    vim.api.nvim_win_set_cursor(s.iwin, { line, col })
    vim.cmd("startinsert")
  end
  return true
end

---Keys that must keep working in the input buffer, so typing must not steal them.
---@return table<string, boolean>
local function reserved_keys()
  local skip = {}
  local leader = vim.g.mapleader
  if leader == nil then
    leader = "\\"
  elseif leader == "<Space>" then
    leader = " "
  end
  if type(leader) == "string" and #leader == 1 then
    skip[leader] = true
  end
  return skip
end

---Type one character in the input buffer and stay in insert mode.
---@param ch string
---@return function
local function type_char(ch)
  return function()
    local cur = vim.api.nvim_win_get_cursor(0)
    local line = vim.api.nvim_buf_get_lines(0, cur[1] - 1, cur[1], false)[1] or ""
    local prefix = (cur[2] >= #line - 1) and "a" or "i"
    vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes(prefix .. ch, true, false, true), "in", false)
  end
end

---Make the input buffer behave like a text field: any printable key types.
---@param buf integer
local function map_typing(buf)
  local skip = reserved_keys()
  for code = 32, 126 do
    local ch = string.char(code)
    if not skip[ch] then
      map(buf, "n", ch, type_char(ch))
    end
  end
end

---@param h {submit:fun(), cancel:fun(), width:integer}
function M.setup(h)
  s.h = h
  s.user_lines = {}
end

function M.owns(win)
  return win == s.twin or win == s.iwin
end

function M.is_open()
  return win_ok(s.twin)
end

function M.open()
  if not buf_ok(s.tbuf) then
    s.tbuf = scratch("vi-ai://chat")
    map(s.tbuf, "n", "q", M.close)
    map(s.tbuf, "n", "<C-c>", s.h.cancel)
    map(s.tbuf, "n", "<C-j>", function()
      M.focus_input(nil, true)
    end)
  end
  if not buf_ok(s.ibuf) then
    s.ibuf = scratch("vi-ai://input")
    map(s.ibuf, "n", "<CR>", s.h.submit)
    map(s.ibuf, "i", "<C-s>", function()
      vim.cmd("stopinsert")
      s.h.submit()
    end)
    map(s.ibuf, { "n", "i" }, "<C-c>", s.h.cancel)
    map(s.ibuf, "n", "<C-k>", function()
      save_input()
      M.focus_chat()
    end)
    map(s.ibuf, "i", "<C-k>", function()
      save_input()
      vim.cmd("stopinsert")
      vim.api.nvim_set_current_win(s.twin)
    end)
    map_typing(s.ibuf)
  end
  if M.is_open() then
    return
  end

  vim.cmd("botright vsplit")
  s.twin = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(s.twin, s.tbuf)
  vim.api.nvim_win_set_width(s.twin, s.h.width)
  style(s.twin)

  vim.cmd("belowright split")
  s.iwin = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(s.iwin, s.ibuf)
  vim.api.nvim_win_set_height(s.iwin, 5)
  style(s.iwin)
  vim.wo[s.iwin].winfixheight = true
  vim.wo[s.iwin].winbar = "<CR> send  <C-s> send (insert)  <C-c> cancel  <C-k> chat  <leader>aa close"

  vim.api.nvim_create_autocmd("WinClosed", {
    pattern = { tostring(s.twin), tostring(s.iwin) },
    once = true,
    callback = function()
      vim.schedule(M.close)
    end,
  })
  M.scroll()
  if s.status then
    M.set_status(s.status)
  end
end

function M.close()
  for _, w in ipairs({ s.iwin, s.twin }) do
    if win_ok(w) and #vim.api.nvim_tabpage_list_wins(0) > 1 then
      vim.api.nvim_win_close(w, true)
    end
  end
  s.twin, s.iwin = nil, nil
end

---Focus the input window.
---@param insert? boolean true/false forces the mode, nil restores the previous one
---@param restore? boolean put the caret back where it was
function M.focus_input(insert, restore)
  if not win_ok(s.iwin) then
    return
  end
  vim.api.nvim_set_current_win(s.iwin)
  if restore and restore_input(insert) then
    return
  end
  if insert then
    local count = buf_ok(s.ibuf) and vim.api.nvim_buf_line_count(s.ibuf) or 1
    vim.api.nvim_win_set_cursor(s.iwin, { count, 0 })
    vim.cmd("startinsert!")
  end
end

function M.focus_chat()
  if win_ok(s.twin) then
    vim.cmd("stopinsert")
    vim.api.nvim_set_current_win(s.twin)
  end
end

---True when the chat view still shows the newest line.
---@return boolean
local function at_bottom()
  if not win_ok(s.twin) or not buf_ok(s.tbuf) then
    return true
  end
  local last = vim.api.nvim_buf_line_count(s.tbuf)
  local ok, bottom = pcall(vim.fn.line, "w$", s.twin)
  if not ok or bottom == -1 then
    return true
  end
  return bottom >= last
end

function M.scroll()
  if win_ok(s.twin) then
    vim.api.nvim_win_set_cursor(s.twin, { vim.api.nvim_buf_line_count(s.tbuf), 0 })
  end
end

---Move the chat cursor to the last user message.
---@return boolean found
function M.goto_last_user()
  if not buf_ok(s.tbuf) or not win_ok(s.twin) then
    return false
  end
  local lines = vim.api.nvim_buf_get_lines(s.tbuf, 0, -1, false)
  local target
  for i = #s.user_lines, 1, -1 do
    local line = s.user_lines[i]
    if line <= #lines and lines[line]:match("^## You") then
      target = line
      break
    end
  end
  if not target then
    for i = #lines, 1, -1 do
      if lines[i]:match("^## You") then
        target = i
        break
      end
    end
  end
  if not target then
    return false
  end
  vim.api.nvim_win_call(s.twin, function()
    vim.api.nvim_win_set_cursor(0, { target, 0 })
    vim.cmd("normal! zz")
  end)
  return true
end

---@param lines string[]
---@param opts? {user:boolean}
function M.append(lines, opts)
  if not buf_ok(s.tbuf) then
    return
  end
  local stick = at_bottom()
  local n = vim.api.nvim_buf_line_count(s.tbuf)
  local empty = n == 1 and vim.api.nvim_buf_get_lines(s.tbuf, 0, 1, false)[1] == ""
  local at = empty and 0 or n
  if s.working_idx then
    at = s.working_idx - 1
  end
  vim.api.nvim_buf_set_lines(s.tbuf, at, at, false, lines)
  if s.working_idx then
    s.working_idx = s.working_idx + #lines
  end
  if opts and opts.user then
    table.insert(s.user_lines, at + 1)
  end
  if stick then
    M.scroll()
  end
end

---Show or replace the live status line at the end of the chat.
---@param text string
function M.set_working(text)
  if not buf_ok(s.tbuf) then
    return
  end
  local stick = at_bottom()
  local lines = vim.api.nvim_buf_get_lines(s.tbuf, 0, -1, false)
  if s.working_idx and lines[s.working_idx] then
    vim.api.nvim_buf_set_lines(s.tbuf, s.working_idx - 1, s.working_idx, false, { text })
  else
    vim.api.nvim_buf_set_lines(s.tbuf, -1, -1, false, { text })
    s.working_idx = vim.api.nvim_buf_line_count(s.tbuf)
  end
  if stick then
    M.scroll()
  end
end

function M.clear_working()
  if not buf_ok(s.tbuf) or not s.working_idx then
    s.working_idx = nil
    return
  end
  local n = vim.api.nvim_buf_line_count(s.tbuf)
  if s.working_idx <= n then
    vim.api.nvim_buf_set_lines(s.tbuf, s.working_idx - 1, s.working_idx, false, {})
  end
  s.working_idx = nil
end

function M.set_status(text)
  s.status = text
  if win_ok(s.twin) then
    vim.wo[s.twin].winbar = text .. "  <C-j> input"
  end
end

function M.take_input()
  if not buf_ok(s.ibuf) then
    return ""
  end
  local text = vim.trim(table.concat(vim.api.nvim_buf_get_lines(s.ibuf, 0, -1, false), "\n"))
  vim.api.nvim_buf_set_lines(s.ibuf, 0, -1, false, {})
  return text
end

function M.set_input(text)
  vim.api.nvim_buf_set_lines(s.ibuf, 0, -1, false, vim.split(text, "\n"))
end

return M
