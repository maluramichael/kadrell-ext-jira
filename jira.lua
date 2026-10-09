-- Reine Funktionen der Jira-Extension: keine Host-Aufrufe, damit sie mit luajit testbar sind (jira_test.lua).

local M = {}

-- Projektpräfix eines Ticket-Keys: alles vor dem letzten Bindestrich. BODO-123 -> BODO, A-B-7 -> A-B.
function M.projectPrefix(key)
  key = tostring(key)
  return key:match("^(.+)%-[^%-]+$") or key
end

-- Mehrzeilige Ordner-Zuordnung "PROJ=/pfad" je Zeile in eine Tabelle. Leerzeilen weg, der Pfad darf "=" enthalten.
function M.parseFolders(text)
  local out = {}
  for line in (tostring(text) .. "\n"):gmatch("([^\n]*)\n") do
    local k, v = line:match("^%s*([^=%s]+)%s*=%s*(.-)%s*$")
    if k and v and v ~= "" then out[k] = v end
  end
  return out
end

-- Query-Wert URL-kodieren (Prozent-Kodierung je Byte), alles außer unreserved.
function M.jqlEncode(s)
  return (tostring(s):gsub("[^%w%-_%.~]", function(c) return string.format("%%%02X", string.byte(c)) end))
end

-- Basic-Auth: base64 von "email:token". Standard-base64, Lua hat keins eingebaut.
local alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
function M.base64(data)
  data = tostring(data)
  return ((data:gsub(".", function(x)
    local r, byte = "", x:byte()
    for i = 8, 1, -1 do r = r .. (byte % 2 ^ i - byte % 2 ^ (i - 1) > 0 and "1" or "0") end
    return r
  end) .. "0000"):gsub("%d%d%d?%d?%d?%d?", function(x)
    if #x < 6 then return "" end
    local c = 0
    for i = 1, 6 do c = c + (x:sub(i, i) == "1" and 2 ^ (6 - i) or 0) end
    return alphabet:sub(c + 1, c + 1)
  end) .. ({ "", "==", "=" })[#data % 3 + 1])
end

-- Antwort von /rest/api/3/search/jql auf eine schlanke Ticket-Liste reduzieren.
function M.mapTickets(decoded)
  local out = {}
  for _, issue in ipairs((decoded and decoded.issues) or {}) do
    local f = issue.fields or {}
    out[#out + 1] = {
      key = issue.key,
      summary = f.summary,
      status = f.status and f.status.name or nil,
      priority = f.priority and f.priority.name or nil,
    }
  end
  return out
end

return M
