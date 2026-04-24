# OpenResty Gateway

Project này đóng gói `OpenResty` bằng Docker để làm web server/reverse proxy ở lớp biên. Cấu hình chạy theo từng domain trong `conf/conf.d`, certificate do `certbot` trên host cấp bằng DNS-01, còn container chỉ mount cert đã có và reload khi cần.

## Luồng Hoạt Động

Luồng request chính:

```text
Client
  -> DNS trỏ domain về server
  -> Docker publish port 443
  -> OpenResty container
  -> server block theo server_name
  -> upstream/backend hoặc response tĩnh
```

Luồng cấu hình:

```text
conf/nginx.conf
  -> include conf/conf.d/*.conf
  -> mỗi file trong conf/conf.d là một domain/server block
```

Luồng TLS:

```text
scripts/create-tls-site.sh
  -> tạo hoặc dùng lại certificate trong /etc/letsencrypt
  -> render config từ conf/templates/tls-site.conf.template
  -> docker exec openresty -t
  -> docker exec openresty -s reload
```

Luồng renew tự động:

```text
certbot.timer
  -> certbot.service
  -> certbot renew
  -> nếu cert được renew thành công
  -> renewal hook reload OpenResty
  -> ghi logs/<domain>.cert.log
```

## Cấu Trúc Chính

```text
conf/
  nginx.conf
  conf.d/
    *.conf
  templates/
    tls-site.conf.template
  examples/

lib/
  gateway/
    auth.lua
    rate_limit.lua
    waf.lua
    waf_rules.lua

scripts/
  create-tls-site.sh
  reload-openresty-after-renew.sh

logs/
  *.access.log
  *.error.log
  *.cert.log

.secrets/
  certbot/
    cloudflare.ini.example

docker-compose.yml
```

## Docker Mount

`docker-compose.yml` mount theo layout sau:

```yaml
volumes:
  - ./conf:/etc/openresty/conf:ro
  - ./conf/nginx.conf:/usr/local/openresty/nginx/conf/nginx.conf:ro
  - ./lib:/etc/openresty/lib:ro
  - ./logs:/var/log/openresty
  - /etc/letsencrypt:/etc/letsencrypt:ro
```

Điểm quan trọng:

- `conf/nginx.conf` được bind vào default config path của image để dùng được `openresty -t` và `openresty -s reload` không cần `-c`.
- `logs/` trên host tương ứng `/var/log/openresty` trong container.
- `/etc/letsencrypt` mount read-only vào container; certbot vẫn chạy ngoài host.
- `.secrets/` không mount vào container.

## Lệnh Vận Hành Nhanh

Start hoặc recreate container:

```bash
docker compose up -d
```

Kiểm tra config:

```bash
docker exec openresty-gateway-mvp openresty -t
```

Reload config/cert:

```bash
docker exec openresty-gateway-mvp openresty -s reload
```

Reopen log sau logrotate:

```bash
docker exec openresty-gateway-mvp openresty -s reopen
```

Tạo site TLS hoặc re-issue cert:

```bash
./scripts/create-tls-site.sh
```

Script có hai chế độ:

```text
1) Create new SSL and config
2) Re-issue SSL only, keep existing config
```

## Log

Mỗi domain nên có log riêng:

```text
logs/<domain>.access.log
logs/<domain>.error.log
logs/<domain>.cert.log
```

Trong đó:

- `access.log`: request log JSON từ OpenResty.
- `error.log`: error log của domain.
- `cert.log`: log thao tác tạo cert, renew cert, test config, reload.

Logrotate nên được cấu hình trên host. Xem hướng dẫn đầy đủ tại [doc/openresty-certbot-dns01.md](doc/openresty-certbot-dns01.md).

## Tài Liệu

- [doc/openresty-certbot-dns01.md](doc/openresty-certbot-dns01.md): cài đặt từ đầu đến cuối, DNS-01, renew hook, logrotate, vận hành.
- [doc/openresty-mvp.md](doc/openresty-mvp.md): ghi chú MVP.
- [doc/openresty-evaluation-test-cases.md](doc/openresty-evaluation-test-cases.md): test case đánh giá.
- [doc/openresty-gateway-plan.md](doc/openresty-gateway-plan.md): kế hoạch gateway dài hạn.
- [doc/openresty-research-plan.md](doc/openresty-research-plan.md): kế hoạch nghiên cứu OpenResty.
