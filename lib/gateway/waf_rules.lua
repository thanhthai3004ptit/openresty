local _M = {}

_M.rules = {
    {
        id = "method-deny-trace",
        target = "method",
        operator = "equals",
        value = "TRACE",
        action = "block",
        message = "http method not allowed"
    },
    {
        id = "user-agent-sqlmap",
        target = "user_agent",
        operator = "contains",
        value = "sqlmap",
        action = "block",
        message = "blocked suspicious user-agent"
    },
    {
        id = "query-sqli-union-select",
        target = "query",
        operator = "regex",
        value = [[union\s+select]],
        action = "block",
        message = "blocked basic sqli pattern"
    },
    {
        id = "query-sqli-or-1-equals-1",
        target = "query",
        operator = "regex",
        value = [[or\s+1=1]],
        action = "block",
        message = "blocked basic sqli boolean pattern"
    },
    {
        id = "query-xss-script-tag",
        target = "query",
        operator = "regex",
        value = [[<\s*script]],
        action = "block",
        message = "blocked basic xss pattern"
    }
}

return _M
