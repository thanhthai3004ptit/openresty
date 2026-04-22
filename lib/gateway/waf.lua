local cjson = require("cjson.safe")
local rules = require("gateway.waf_rules").rules

local _M = {}

local function get_target_value(target)
    if target == "method" then
        return ngx.req.get_method()
    end

    if target == "query" then
        return ngx.unescape_uri(ngx.var.args or "")
    end

    if target == "uri" then
        return ngx.unescape_uri(ngx.var.request_uri or "")
    end

    if target == "user_agent" then
        return ngx.var.http_user_agent or ""
    end

    if target == "ip" then
        return ngx.var.remote_addr or ""
    end

    return ""
end

local function match_rule(rule, value)
    if rule.operator == "equals" then
        return value == rule.value
    end

    if rule.operator == "contains" then
        return value:lower():find(rule.value:lower(), 1, true) ~= nil
    end

    if rule.operator == "regex" then
        return ngx.re.find(value, rule.value, "ijo") ~= nil
    end

    return false
end

local function block_request(rule, inspected_value)
    ngx.log(
        ngx.WARN,
        "waf block rule_id=", rule.id,
        " remote_addr=", ngx.var.remote_addr or "-",
        " host=", ngx.var.host or "-",
        " method=", ngx.req.get_method() or "-",
        " uri=", ngx.var.request_uri or "-",
        " inspected_value=", inspected_value or ""
    )

    ngx.status = ngx.HTTP_FORBIDDEN
    ngx.header["Content-Type"] = "application/json"
    ngx.say(cjson.encode({
        error = "waf_blocked",
        rule_id = rule.id,
        message = rule.message
    }))
    return ngx.exit(ngx.HTTP_FORBIDDEN)
end

function _M.check()
    for _, rule in ipairs(rules) do
        local value = get_target_value(rule.target)
        if value ~= "" and match_rule(rule, value) then
            return block_request(rule, value)
        end
    end
end

return _M
