local M = {}

local function relpath(path, root)
  if path == "" then
    return "[No Name]"
  end
  if path:sub(1, #root + 1) == root .. "/" then
    return path:sub(#root + 2)
  end
  return path
end

local function numbered(lines, first, mark)
  local out = {}
  for i, line in ipairs(lines) do
    local n = first + i - 1
    out[#out + 1] = string.format("%s%4d | %s", n == mark and ">>>" or "   ", n, line)
  end
  return out
end

local function diagnostics(buf, first, last)
  local out = {}
  for _, d in ipairs(vim.diagnostic.get(buf)) do
    local line = d.lnum + 1
    if line >= first and line <= last then
      out[#out + 1] = string.format("line %d [%s] %s", line, vim.diagnostic.severity[d.severity], d.message)
    end
  end
  return out
end

local function open_buffers(root, current)
  local out = {}
  for _, b in ipairs(vim.api.nvim_list_bufs()) do
    local name = vim.api.nvim_buf_get_name(b)
    if b ~= current and vim.bo[b].buflisted and vim.bo[b].buftype == "" and name ~= "" then
      out[#out + 1] = relpath(name, root)
    end
  end
  return out
end

---Describe where the user is in `win` as plain text for the model.
---@param opts {root:string, whole:boolean, radius:integer, max_lines:integer, selection?:integer[]}
function M.build(win, opts)
  local buf = vim.api.nvim_win_get_buf(win)
  local row, col = unpack(vim.api.nvim_win_get_cursor(win))
  local total = vim.api.nvim_buf_line_count(buf)
  local ft = vim.bo[buf].filetype

  local first, last, label
  if opts.selection then
    first, last, label = opts.selection[1], opts.selection[2], "selected lines"
  elseif opts.whole then
    first, last, label = 1, math.min(total, opts.max_lines), "document"
  else
    first, last, label = math.max(1, row - opts.radius), math.min(total, row + opts.radius), "code around cursor"
  end

  local out = {
    string.format("file: %s (%s)", relpath(vim.api.nvim_buf_get_name(buf), opts.root), ft),
    string.format("cursor: line %d, col %d (file has %d lines)", row, col + 1, total),
    string.format("%s, lines %d-%d (cursor line marked >>>):", label, first, last),
    "```" .. ft,
  }
  vim.list_extend(out, numbered(vim.api.nvim_buf_get_lines(buf, first - 1, last, false), first, row))
  out[#out + 1] = "```"

  local diags = diagnostics(buf, first, last)
  if #diags > 0 then
    out[#out + 1] = "diagnostics:"
    vim.list_extend(out, diags)
  end

  local bufs = open_buffers(opts.root, buf)
  if #bufs > 0 then
    out[#out + 1] = "other open buffers: " .. table.concat(bufs, ", ")
  end

  return table.concat(out, "\n")
end

return M
