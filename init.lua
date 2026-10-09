-- Jira-Extension: Tickets aus einer oder mehreren Jira-Cloud-Instanzen in der rechten Sidebar.
-- Spec: docs/superpowers/specs/2026-10-09-jira-extension-design.md. Host-Aufrufe nur in Handlern.

local jira = require("jira")

-- Sprache aus der Kadrell-Einstellung (de/en), Englisch als Rückfall.
local lang = (kadrell.locale or "en"):sub(1, 2)
local T = {
  en = { browser = "Open in browser", folder = "Open in project folder", reload = "Reload",
         remove = "Remove instance", notLoggedIn = "Not logged in", noFolder = "No folder mapped for ",
         noInstances = "Add a Jira instance in settings (Cmd+,)" },
  de = { browser = "Im Browser öffnen", folder = "Im Projektordner öffnen", reload = "Aktualisieren",
         remove = "Instanz entfernen", notLoggedIn = "Nicht angemeldet", noFolder = "Kein Ordner für ",
         noInstances = "Jira-Instanz in den Einstellungen anlegen (Cmd+,)" },
}
local function tr(k) return (T[lang] or T.en)[k] or k end

-- In-Memory-Stand, in Handlern aus storage/secret gefüllt; render() liest nur hieraus.
local G = { instances = {}, tickets = {}, errors = {}, folders = {} }

local function host(base) return (base:gsub("^https?://", "")) end

local function ticketNode(inst, t)
  local prefix = jira.projectPrefix(t.key)
  local folder = (G.folders[inst.baseUrl] or {})[prefix]
  local actions = { { id = "open:" .. inst.baseUrl .. "/browse/" .. t.key, label = tr("browser") } }
  if folder then table.insert(actions, { id = "folder:" .. inst.baseUrl .. ":" .. t.key, label = tr("folder") }) end
  local detail = (t.status or "") .. (t.priority and (" · " .. t.priority) or "")
  return { type = "item", text = t.key .. " " .. (t.summary or ""), detail = detail, color = "accent", actions = actions }
end

local function instanceSection(inst)
  local children = {}
  if G.errors[inst.baseUrl] then table.insert(children, { type = "text", text = G.errors[inst.baseUrl], color = "err" }) end
  for _, t in ipairs(G.tickets[inst.baseUrl] or {}) do table.insert(children, ticketNode(inst, t)) end
  table.insert(children, { type = "button", label = tr("remove"), action = "rm:" .. inst.baseUrl })
  return { type = "section", title = host(inst.baseUrl), children = children }
end

local function render()
  local children = {}
  if #G.instances == 0 then table.insert(children, { type = "text", text = tr("noInstances"), color = "muted" }) end
  for _, inst in ipairs(G.instances) do table.insert(children, instanceSection(inst)) end
  table.insert(children, { type = "button", label = tr("reload"), action = "refresh" })
  kadrell.panel.set{ title = "Jira", children = children }
end

-- Eine Instanz abfragen; Fehler landen als Kurzgrund im Abschnitt, die anderen Instanzen bleiben sichtbar.
local function fetch(inst, token)
  local url = inst.baseUrl .. "/rest/api/3/search/jql?jql=" .. jira.jqlEncode(inst.jql or "")
    .. "&fields=summary,status,priority&maxResults=50"
  -- Endpunkt /rest/api/3/search/jql (der alte /rest/api/3/search wurde Ende 2025 abgeschaltet); gibt per Default nur id
  -- zurück, daher fields explizit. Quelle: developer.atlassian.com/cloud/jira/platform/rest/v3 (Issue search).
  local resp = kadrell.http{ method = "GET", url = url,
    headers = { Authorization = "Basic " .. jira.base64((inst.email or "") .. ":" .. token), Accept = "application/json" } }
  if resp.status < 200 or resp.status >= 300 then
    G.errors[inst.baseUrl] = "HTTP " .. tostring(resp.status); render(); return
  end
  local ok, decoded = pcall(kadrell.json.decode, resp.body)
  if not ok or type(decoded) ~= "table" then G.errors[inst.baseUrl] = "decode error"; render(); return end
  local tickets = jira.mapTickets(decoded)
  G.tickets[inst.baseUrl] = tickets
  G.errors[inst.baseUrl] = nil
  kadrell.storage.set("cache:" .. inst.baseUrl, tickets)
  render()
end

local function refresh()
  local instances = kadrell.storage.get("instances") or {}
  G.instances = instances
  for _, inst in ipairs(instances) do
    G.folders[inst.baseUrl] = jira.parseFolders(inst.folders or "")
    local token = kadrell.secret.get("token:" .. inst.baseUrl)
    if not token then
      G.errors[inst.baseUrl] = tr("notLoggedIn")
      G.tickets[inst.baseUrl] = nil
    else
      G.tickets[inst.baseUrl] = kadrell.storage.get("cache:" .. inst.baseUrl) -- gecachten Stand sofort zeigen
      fetch(inst, token)
    end
  end
  render()
end

-- Das Einstellungsformular trägt eine Instanz ein oder aktualisiert sie (Schlüssel = baseUrl), Token in den Schlüsselbund.
local function upsertInstance()
  local base = kadrell.config.baseUrl
  if not base or base == "" then return end
  base = base:gsub("/+$", "")
  local instances = kadrell.storage.get("instances") or {}
  local inst
  for _, i in ipairs(instances) do if i.baseUrl == base then inst = i end end
  if not inst then inst = { baseUrl = base }; table.insert(instances, inst) end
  inst.email, inst.jql, inst.folders = kadrell.config.email, kadrell.config.jql, kadrell.config.folders
  kadrell.storage.set("instances", instances)
  if kadrell.config.token and #kadrell.config.token > 0 then kadrell.secret.set("token:" .. base, kadrell.config.token) end
end

local function openFolder(base, key)
  local prefix = jira.projectPrefix(key)
  local folder = (G.folders[base] or {})[prefix]
  if not folder then kadrell.warn(tr("noFolder") .. prefix); return end
  local r = kadrell.run("new", "-c", folder)
  if r.status ~= 0 then kadrell.warn("new failed: " .. tostring(r.stderr)) end
end

local function removeInstance(base)
  local instances, out = kadrell.storage.get("instances") or {}, {}
  for _, inst in ipairs(instances) do if inst.baseUrl ~= base then table.insert(out, inst) end end
  kadrell.storage.set("instances", out)
  kadrell.secret.delete("token:" .. base)
  kadrell.storage.set("cache:" .. base, nil)
  refresh()
end

kadrell.on("ui.action", function(data)
  local id = data.id or ""
  if id == "refresh" then return refresh() end
  local url = id:match("^open:(.+)$")
  if url then return (function() kadrell.exec({ "open", url }) end)() end
  local base, key = id:match("^folder:(.+):([^:]+)$")
  if base and key then return openFolder(base, key) end
  local rbase = id:match("^rm:(.+)$")
  if rbase then return removeInstance(rbase) end
end)

kadrell.on("app.ready", function()
  upsertInstance()
  refresh()
end)

kadrell.every(300, refresh)

-- Beim Laden sofort etwas zeigen (leer oder Hinweis), bevor app.ready die Daten holt.
render()
