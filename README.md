# Cổng điều phối OpenResty

## Giới thiệu

Đây là dự án xây dựng cổng điều phối trên nền `OpenResty`, hướng tới vai trò xử lý lưu lượng ở lớp biên và lớp API. Mục tiêu của dự án là tạo ra một nền tảng có thể mở rộng dần để đảm nhiệm các nhóm chức năng sau:

- chuyển tiếp yêu cầu và định tuyến đến dịch vụ phù hợp
- xác thực và phân quyền ngay tại cổng điều phối
- giới hạn tốc độ và kiểm soát lưu lượng
- lọc yêu cầu và chặn các mẫu tấn công cơ bản
- ghi log, lưu vết và phục vụ quan sát hệ thống

Mã nguồn hiện tại đang ở giai đoạn thử nghiệm kỹ thuật và xây dựng mẫu ban đầu, nhưng cách tổ chức đã hướng tới việc phát triển tiếp thành một dự án dùng được trong môi trường thực tế.

## Hướng tiếp cận kiến trúc

Hệ thống được tổ chức theo cách:

- `NGINX/OpenResty` làm lõi tiếp nhận và xử lý yêu cầu
- `Lua` đảm nhiệm phần logic bổ sung ở tầng cổng điều phối
- tệp cấu hình nginx giữ phần khung của luồng xử lý
- các mô-đun Lua giữ phần chính sách và xử lý động

Trong cách tổ chức hiện nay:

- `nginx.conf` giữ cấu hình chung
- `conf.d/*.conf` đại diện cho từng miền hoặc từng khối `server`
- `lib/gateway/*.lua` chứa các mô-đun logic có thể dùng lại

## Những khả năng hiện có

Phiên bản hiện tại đã có các khả năng nền tảng sau:

- định tuyến theo tên miền trong `server_name`
- chuyển tiếp yêu cầu tới dịch vụ phía sau
- kiểm tra `JWT` cho các tuyến yêu cầu bảo vệ
- giới hạn tốc độ theo cửa sổ thời gian cố định
- chặn một số mẫu tấn công bằng WAF mức nhẹ
- tách log truy cập và log lỗi theo từng miền

Những phần này chủ yếu phục vụ cho:

- nghiên cứu mức độ phù hợp của OpenResty
- kiểm chứng các bài toán thường gặp của một cổng điều phối
- chuẩn bị cho việc đo đạc và so sánh hiệu năng

## Các phần chính của hệ thống

### Phần cấu hình

- [conf/nginx.conf](/home/thaint/Documents/openresty/conf/nginx.conf)
  - tệp cấu hình gốc của OpenResty
  - khai báo đường dẫn nạp mô-đun Lua, vùng nhớ dùng chung, định dạng log và việc nạp các tệp cấu hình site

- [conf/conf.d/gateway.conf](/home/thaint/Documents/openresty/conf/conf.d/gateway.conf)
  - cấu hình cho cổng điều phối chính
  - chứa các tuyến công khai và các tuyến yêu cầu xác thực

- [conf/conf.d/admin.conf](/home/thaint/Documents/openresty/conf/conf.d/admin.conf)
  - cấu hình cho miền quản trị hoặc miền minh họa tách riêng

### Phần logic Lua

- [lib/gateway/init.lua](/home/thaint/Documents/openresty/lib/gateway/init.lua)
  - mô-đun khởi tạo cơ bản

- [lib/gateway/auth.lua](/home/thaint/Documents/openresty/lib/gateway/auth.lua)
  - xử lý việc kiểm tra `JWT`

- [lib/gateway/rate_limit.lua](/home/thaint/Documents/openresty/lib/gateway/rate_limit.lua)
  - xử lý giới hạn tốc độ

- [lib/gateway/waf.lua](/home/thaint/Documents/openresty/lib/gateway/waf.lua)
  - bộ máy lọc và chặn yêu cầu mức nhẹ

- [lib/gateway/waf_rules.lua](/home/thaint/Documents/openresty/lib/gateway/waf_rules.lua)
  - tập luật dùng cho bộ lọc yêu cầu

## Cấu trúc thư mục

```text
conf/
  nginx.conf
  conf.d/
    gateway.conf
    admin.conf
  env/
    dev.env.example

lib/
  gateway/
    init.lua
    auth.lua
    rate_limit.lua
    waf.lua
    waf_rules.lua

logs/

doc/
  openresty-gateway-plan.md
  openresty-research-plan.md
  openresty-mvp.md
  openresty-evaluation-test-cases.md

docker-compose.yml
```

## Nguyên tắc tổ chức mã nguồn

Dự án hiện được giữ theo các nguyên tắc sau:

- mỗi tệp trong `conf.d` tương ứng với một khối `server` hoặc một miền
- logic dùng lại được đặt trong `lib/gateway`
- cấu hình chung và cấu hình theo từng miền được tách riêng
- log được chia theo từng miền để thuận tiện khi vận hành
- các dịch vụ phục vụ việc thử nghiệm như dịch vụ phía sau hoặc dịch vụ phát hành token được tách thành dự án riêng

## Log và vận hành

Hệ thống hiện ghi log ở hai mức:

- log lỗi chung của toàn bộ tiến trình
- log truy cập và log lỗi riêng theo từng miền

Các tệp log được ánh xạ ra máy chủ chạy Docker để phục vụ:

- theo dõi hoạt động
- tra cứu khi có sự cố
- đối chiếu khi đo đạc hiệu năng

Các tệp log hiện có:

- [logs/error.log](/home/thaint/Documents/openresty/logs/error.log)
- [logs/gateway-test.local.access.log](/home/thaint/Documents/openresty/logs/gateway-test.local.access.log)
- [logs/gateway-test.local.error.log](/home/thaint/Documents/openresty/logs/gateway-test.local.error.log)
- [logs/admin-test.local.access.log](/home/thaint/Documents/openresty/logs/admin-test.local.access.log)
- [logs/admin-test.local.error.log](/home/thaint/Documents/openresty/logs/admin-test.local.error.log)

## Môi trường chạy hiện tại

Repo này được đóng gói bằng Docker để phục vụ phát triển cục bộ và thử nghiệm kỹ thuật.

Cổng điều phối hiện được chạy theo cách:

- dùng `docker compose`
- ánh xạ toàn bộ mã nguồn vào bên trong vùng làm việc của container
- khởi động OpenResty với tệp cấu hình chính tại `conf/nginx.conf`

Ngoài cổng điều phối, luồng thử nghiệm hiện tại có thể kết hợp với:

- `backend-test`
  - dịch vụ phía sau dùng để minh họa việc chuyển tiếp yêu cầu
- `auth-test`
  - dịch vụ phát hành token dùng cho luồng đăng nhập và lấy `JWT`

Hai dự án này là thành phần hỗ trợ cho việc nghiên cứu và thử nghiệm, không phải là phần bắt buộc của kiến trúc cổng điều phối lâu dài.

## Phạm vi hiện tại và các giới hạn

Những gì hiện đã có:

- cấu hình miền tĩnh
- tuyến chuyển tiếp cơ bản
- xác thực `JWT` theo `HS256`
- giới hạn tốc độ ở mức cơ bản
- bộ lọc yêu cầu mức nhẹ dựa trên biểu thức mẫu
- ghi log ra tệp

Những gì chưa có hoặc mới chỉ ở mức tối thiểu:

- kho cấu hình động
- giao diện hoặc API quản trị
- cơ chế tìm kiếm dịch vụ
- kiểm tra sức khỏe chủ động
- thử lại hoặc ngắt mạch
- số liệu theo dõi và truy vết
- quản lý bí mật theo chuẩn vận hành
- cơ chế chấm điểm hoặc phát hiện bất thường cho WAF
- tích hợp `OAuth/OIDC` đúng chuẩn

## Hướng phát triển tiếp theo

Lộ trình mở rộng hợp lý cho dự án này:

1. chuẩn hóa phần quan sát hệ thống
2. bổ sung cấu hình động cho tuyến và chính sách
3. thêm số liệu theo dõi và truy vết
4. chuyển khóa bí mật sang cơ chế quản lý phù hợp hơn
5. nâng cấp bộ lọc mức nhẹ thành bộ máy chính sách có chế độ phát hiện và chế độ chặn
6. bổ sung quản lý dịch vụ phía sau, khả năng chịu lỗi và phần quản trị

## Cách sử dụng README này

README này tập trung vào:

- giới thiệu dự án
- kiến trúc và các mô-đun chính
- nguyên tắc tổ chức mã nguồn
- hướng phát triển về sau

Phần hướng dẫn kiểm thử và đánh giá chi tiết được tách sang các tài liệu riêng:

- [doc/openresty-mvp.md](/home/thaint/Documents/openresty/doc/openresty-mvp.md)
- [doc/openresty-evaluation-test-cases.md](/home/thaint/Documents/openresty/doc/openresty-evaluation-test-cases.md)

Phần kế hoạch và nghiên cứu:

- [doc/openresty-gateway-plan.md](/home/thaint/Documents/openresty/doc/openresty-gateway-plan.md)
- [doc/openresty-research-plan.md](/home/thaint/Documents/openresty/doc/openresty-research-plan.md)
