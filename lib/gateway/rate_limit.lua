local _M = {}

local function respond_too_many_requests(limit, remaining, window)
    ngx.header["Content-Type"] = "application/json"
    ngx.header["X-RateLimit-Limit"] = tostring(limit)
    ngx.header["X-RateLimit-Remaining"] = tostring(remaining)
    ngx.header["X-RateLimit-Window"] = tostring(window)
    ngx.header["Retry-After"] = tostring(window)
    ngx.status = ngx.HTTP_TOO_MANY_REQUESTS
    ngx.say(string.format(
        '{"error":"rate_limit_exceeded","limit":%d,"remaining":%d,"window":%d}',
        limit,
        remaining,
        window
    ))
    return ngx.exit(ngx.HTTP_TOO_MANY_REQUESTS)
end

function _M.check(opts)
    local dict = ngx.shared.rate_limit_store
    local key = string.format("ratelimit:%s", opts.key or "unknown")
    local limit = opts.limit or 60
    local window = opts.window or 60

    local current, err = dict:incr(key, 1, 0, window)
    if not current then
        ngx.log(ngx.ERR, "failed to update rate limit counter: ", err)
        return ngx.exit(ngx.HTTP_INTERNAL_SERVER_ERROR)
    end

    local remaining = math.max(limit - current, 0)
    ngx.header["X-RateLimit-Limit"] = tostring(limit)
    ngx.header["X-RateLimit-Remaining"] = tostring(remaining)
    ngx.header["X-RateLimit-Window"] = tostring(window)

    if current > limit then
        return respond_too_many_requests(limit, remaining, window)
    end
end

return _M
