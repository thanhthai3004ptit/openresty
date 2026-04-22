# OpenResty MVP

Day la MVP OpenResty dau tien trong workspace nay, duoc dung de phuc vu 2 muc tieu:

- Lam skeleton ky thuat cho gateway MVP
- Lam PoC cho tai lieu research/evaluation OpenResty

## MVP hien co

- Site-based config theo kieu `conf.d/*.conf`
- Lua request policy trong `access_by_lua*`
- Route `/api/demo` proxy toi backend test bang domain local
- Route `/api/secure-demo` duoc bao ve bang JWT
- Rate limiting theo IP bang `lua_shared_dict`
- Site-specific access log
- Health endpoint
- Docker Compose de chay local
- Log file duoc luu trong repo va mount ra host

## Cau truc

```text
conf/
  conf.d/
    admin.conf
    gateway.conf
  env/
    dev.env.example
  nginx.conf
lib/
  gateway/
    auth.lua
    init.lua
    rate_limit.lua
logs/
  error.log
  gateway-test.local.access.log
  gateway-test.local.error.log
  admin-test.local.access.log
  admin-test.local.error.log
docker-compose.yml
doc/
```

`conf/nginx.conf` giu cac phan global/http-level, con tung `site` duoc tach rieng trong `conf/conf.d/*.conf`.
Log duoc ghi theo site trong `logs/*.access.log` va `logs/*.error.log`, dong thoi van giu `logs/error.log` lam global error log toi thieu o muc `warn`.

## Cach chay

```bash
docker compose up
```

Xem log tren host:

```bash
tail -f logs/error.log
tail -f logs/gateway-test.local.access.log
tail -f logs/gateway-test.local.error.log
tail -f logs/admin-test.local.access.log
tail -f logs/admin-test.local.error.log
```

Gateway se mo o:

- `http://localhost:8080/` voi header `Host: gateway-test.local`
- `http://localhost:8080/health` voi header `Host: gateway-test.local`
- `http://localhost:8080/api/demo` voi header `Host: gateway-test.local`
- `http://localhost:8080/api/secure-demo` voi header `Host: gateway-test.local`
- `http://localhost:8080/` voi header `Host: admin-test.local`

## Cach test nhanh

```bash
curl -H 'Host: gateway-test.local' http://localhost:8080/health
curl -H 'Host: gateway-test.local' http://localhost:8080/api/demo
curl -H 'Host: admin-test.local' http://localhost:8080/
```

Tao JWT local de test `secure-demo`:

```bash
python3 - <<'PY'
import base64, hashlib, hmac, json, time

def b64url(data):
    return base64.urlsafe_b64encode(data).rstrip(b"=").decode()

header = b64url(json.dumps({"alg":"HS256","typ":"JWT"}, separators=(",", ":")).encode())
payload = b64url(json.dumps({
    "sub": "demo-user",
    "iss": "backend-test-auth",
    "aud": "gateway-test",
    "exp": int(time.time()) + 3600
}, separators=(",", ":")).encode())
signing_input = f"{header}.{payload}".encode()
signature = b64url(hmac.new(b"openresty-dev-secret", signing_input, hashlib.sha256).digest())
print(f"{header}.{payload}.{signature}")
PY
```

Sau do goi:

```bash
curl -H 'Host: gateway-test.local' \
  -H "Authorization: Bearer <JWT_TOKEN>" \
  http://localhost:8080/api/secure-demo
```

Rate limit hien tai:

- 5 request / 60 giay / IP cho duong dan `/api/*`

Co the test vuot nguong:

```bash
for i in $(seq 1 7); do curl -i -H 'Host: gateway-test.local' http://localhost:8080/api/demo; done
```

## MVP nay phu hop voi research objective nao

- Architecture overview: minh hoa `access_by_lua*`
- Core features: site-based config + Lua logic
- Performance evaluation: co the benchmark luong request qua gateway
- Use cases: API gateway skeleton, rate limiting, security filtering co ban
- Deployment and operations: co the chay bang Docker Compose

## Gioi han hien tai

- Chua co JWT auth
- Chua co dynamic routing
- Chua co Redis/external config store
- Chua co metrics/tracing
- Chua co WAF-lite rules
- JWT verification dang o muc MVP voi `HS256` va secret hard-code

## Buoc tiep theo hop ly

- Them `JWT validation`
- Them `request ID` va structured audit log chi tiet hon
- Them metrics endpoint
- Noi upstream that vao tung site/route khi backend san sang
