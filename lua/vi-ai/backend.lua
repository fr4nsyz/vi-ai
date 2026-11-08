local M = {}

---Run one opencode turn. Returns the vim.SystemObj (call :kill() to cancel).
---@param args {agent:string, model?:string, session?:string, cwd:string, prompt:string}
---@param on_event fun(ev:table)
---@param on_done fun(code:integer, stderr:string)
function M.send(args, on_event, on_done)
  local cmd = { "opencode", "run", "--format", "json", "--agent", args.agent }
  if args.model then
    vim.list_extend(cmd, { "--model", args.model })
  end
  if args.session then
    vim.list_extend(cmd, { "--session", args.session })
  end

  local pending = ""
  local function emit(line)
    local ok, ev = pcall(vim.json.decode, line)
    if ok and type(ev) == "table" then
      vim.schedule(function()
        on_event(ev)
      end)
    end
  end

  local stderr = {}
  -- Prompt goes through stdin: opencode reads a piped stdin as the message and ignores argv.
  return vim.system(cmd, {
    cwd = args.cwd,
    stdin = args.prompt,
    stdout = function(_, data)
      if not data then
        if pending ~= "" then
          emit(pending)
        end
        return
      end
      pending = pending .. data
      local nl = pending:find("\n", 1, true)
      while nl do
        emit(pending:sub(1, nl - 1))
        pending = pending:sub(nl + 1)
        nl = pending:find("\n", 1, true)
      end
    end,
    stderr = function(_, data)
      if data then
        table.insert(stderr, data)
      end
    end,
  }, function(res)
    vim.schedule(function()
      on_done(res.code, table.concat(stderr))
    end)
  end)
end

---@param cb fun(models:string[])
function M.models(cb)
  vim.system({ "opencode", "models" }, { text = true }, function(res)
    local list = vim.tbl_filter(function(l)
      return l ~= ""
    end, vim.split(res.stdout or "", "\n"))
    vim.schedule(function()
      cb(list)
    end)
  end)
end

return M
