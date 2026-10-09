-- Selbsttest der reinen Funktionen: luajit jira_test.lua (aus dem Extension-Ordner).
local jira = require("jira")

local function eq(a, b, msg)
  assert(a == b, (msg or "") .. ": expected [" .. tostring(b) .. "] got [" .. tostring(a) .. "]")
end

eq(jira.projectPrefix("BODO-123"), "BODO", "prefix simple")
eq(jira.projectPrefix("A-B-7"), "A-B", "prefix nested")
eq(jira.projectPrefix("NOPREFIX"), "NOPREFIX", "prefix none")

local f = jira.parseFolders("BODO=/Users/m/bodo\n\n  ACME = /tmp/acme \nX=/p/a=b")
eq(f.BODO, "/Users/m/bodo", "folder simple")
eq(f.ACME, "/tmp/acme", "folder trimmed")
eq(f.X, "/p/a=b", "folder eq in path")

eq(jira.jqlEncode("a b&c"), "a%20b%26c", "jql encode")
eq(jira.base64("user:tok"), "dXNlcjp0b2s=", "base64")
eq(jira.base64("Aladdin:open sesame"), "QWxhZGRpbjpvcGVuIHNlc2FtZQ==", "base64 rfc example")

local decoded = { issues = {
  { key = "BODO-1", fields = { summary = "Login", status = { name = "In Progress" }, priority = { name = "High" } } },
  { key = "BODO-2", fields = { summary = "Logout" } },
} }
local t = jira.mapTickets(decoded)
eq(#t, 2, "two tickets")
eq(t[1].key, "BODO-1", "key")
eq(t[1].status, "In Progress", "status")
eq(t[1].priority, "High", "priority")
eq(t[2].summary, "Logout", "summary")
eq(t[2].status, nil, "missing status")
eq(#jira.mapTickets(nil), 0, "nil response")

print("jira_test: OK")
