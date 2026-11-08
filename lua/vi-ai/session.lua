local M = {}

local path = vim.fn.stdpath("data") .. "/vi-ai.json"
local data

local function load()
  if data then
    return data
  end
  data = {}
  local f = io.open(path, "r")
  if f then
    local ok, decoded = pcall(vim.json.decode, f:read("*a"))
    f:close()
    if ok and type(decoded) == "table" then
      data = decoded
    end
  end
  data.sessions = data.sessions or {}
  return data
end

local function save()
  vim.fn.mkdir(vim.fs.dirname(path), "p")
  local f = io.open(path, "w")
  if f then
    f:write(vim.json.encode(data))
    f:close()
  end
end

function M.get(key)
  return load().sessions[key]
end

function M.set(key, id)
  load().sessions[key] = id
  save()
end

function M.model()
  return load().model
end

function M.set_model(model)
  load().model = model
  save()
end

return M
