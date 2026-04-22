local cjson = require("cjson.safe")
local bit = require("bit")
local sha256 = require("resty.sha256")

local _M = {}
local BLOCK_SIZE = 64

local function sha256_digest(input)
    local hash = sha256:new()
    hash:update(input)
    return hash:final()
end

local function xor_with_byte(input, byte_value)
    local out = {}
    for i = 1, #input do
        out[i] = string.char(bit.bxor(input:byte(i), byte_value))
    end
    return table.concat(out)
end

local function hmac_sha256(key, message)
    if #key > BLOCK_SIZE then
        key = sha256_digest(key)
    end

    if #key < BLOCK_SIZE then
        key = key .. string.rep("\0", BLOCK_SIZE - #key)
    end

    local o_key_pad = xor_with_byte(key, 0x5c)
    local i_key_pad = xor_with_byte(key, 0x36)

    return sha256_digest(o_key_pad .. sha256_digest(i_key_pad .. message))
end

local function decode_base64url(input)
    if not input then
        return nil
    end

    local base64 = input:gsub("-", "+"):gsub("_", "/")
    local padding = #base64 % 4
    if padding > 0 then
        base64 = base64 .. string.rep("=", 4 - padding)
    end

    return ngx.decode_base64(base64)
end

local function encode_base64url(input)
    local encoded = ngx.encode_base64(input)
    return encoded:gsub("%+", "-"):gsub("/", "_"):gsub("=", "")
end

local function json_error(status, body)
    ngx.status = status
    ngx.header["Content-Type"] = "application/json"
    ngx.say(cjson.encode(body))
    return ngx.exit(status)
end

local function extract_bearer_token()
    local header = ngx.var.http_authorization
    if not header then
        return nil, "missing_authorization_header"
    end

    local token = header:match("^Bearer%s+(.+)$")
    if not token then
        return nil, "invalid_authorization_scheme"
    end

    return token
end

local function verify_signature(signing_input, signature, secret)
    local expected = encode_base64url(hmac_sha256(secret, signing_input))
    return expected == signature
end

function _M.check_jwt(opts)
    local token, token_err = extract_bearer_token()
    if not token then
        return json_error(ngx.HTTP_UNAUTHORIZED, {
            error = token_err
        })
    end

    local header_b64, payload_b64, signature = token:match("^([^.]+)%.([^.]+)%.([^.]+)$")
    if not header_b64 or not payload_b64 or not signature then
        return json_error(ngx.HTTP_UNAUTHORIZED, {
            error = "invalid_jwt_format"
        })
    end

    local header_raw = decode_base64url(header_b64)
    local payload_raw = decode_base64url(payload_b64)
    if not header_raw or not payload_raw then
        return json_error(ngx.HTTP_UNAUTHORIZED, {
            error = "invalid_jwt_encoding"
        })
    end

    local header = cjson.decode(header_raw)
    local payload = cjson.decode(payload_raw)
    if not header or not payload then
        return json_error(ngx.HTTP_UNAUTHORIZED, {
            error = "invalid_jwt_payload"
        })
    end

    if header.alg ~= "HS256" then
        return json_error(ngx.HTTP_UNAUTHORIZED, {
            error = "unsupported_jwt_alg"
        })
    end

    if not verify_signature(header_b64 .. "." .. payload_b64, signature, opts.secret) then
        return json_error(ngx.HTTP_UNAUTHORIZED, {
            error = "invalid_jwt_signature"
        })
    end

    local now = ngx.time()
    if payload.exp and payload.exp < now then
        return json_error(ngx.HTTP_UNAUTHORIZED, {
            error = "jwt_expired"
        })
    end

    if payload.nbf and payload.nbf > now then
        return json_error(ngx.HTTP_UNAUTHORIZED, {
            error = "jwt_not_yet_valid"
        })
    end

    if opts.issuer and payload.iss ~= opts.issuer then
        return json_error(ngx.HTTP_UNAUTHORIZED, {
            error = "invalid_jwt_issuer"
        })
    end

    if opts.audience and payload.aud ~= opts.audience then
        return json_error(ngx.HTTP_UNAUTHORIZED, {
            error = "invalid_jwt_audience"
        })
    end

    ngx.req.set_header("X-Authenticated-Sub", payload.sub or "unknown")
    ngx.req.set_header("X-Authenticated-Iss", payload.iss or "")
    ngx.ctx.authenticated_jwt = payload
end

return _M
