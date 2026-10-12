# Bài 4: Docker Custom Network và Named Volume

## 1. Mục tiêu

- Tạo Docker Network để các container giao tiếp với nhau bằng tên.
- Tạo Named Volume để lưu trữ dữ liệu PostgreSQL độc lập với vòng đời container.
- Triển khai Backend Node.js kết nối với PostgreSQL.
- Kiểm tra dữ liệu sau khi xóa và tạo lại container Database.

## 2. Môi trường

- Docker Engine
- PostgreSQL 15 Alpine
- Node.js 20 Alpine
- Backend image: `homework-backend:v1`

## 3. Tài nguyên Docker

| Tài nguyên | Tên |
|---|---|
| Network | `app-net` |
| Named Volume | `db-data` |
| Database container | `db-server` |
| Backend container | `app-container` |
| Database | `appdb` |
| Backend port | `8080:3000` |

## 4. Cách thực hiện

Chạy script để tạo Network, Volume, build Backend image và khởi chạy các container:

```bash
chmod +x commands.sh
./commands.sh
```

Script tự động thực hiện các công việc:

1. Tạo Docker Network `app-net`.
2. Tạo Named Volume `db-data`.
3. Build Backend image `homework-backend:v1`.
4. Khởi chạy PostgreSQL và gắn volume vào `/var/lib/postgresql/data`.
5. Chờ PostgreSQL sẵn sàng trước khi khởi chạy Backend.
6. Kiểm tra kết nối mạng nội bộ giữa Backend và Database.
7. Tạo bảng `students` và thêm dữ liệu thử nghiệm.
8. Gọi API `/health` và `/students`.
9. Xóa container Database cũ và tạo lại container sử dụng volume cũ.
10. Kiểm tra dữ liệu sau khi khôi phục, kết nối mạng và trạng thái các tài nguyên.

## 5. Kết quả kiểm tra thực tế

### 5.1. Docker Network

Network `app-net` được tạo thành công. Backend kết nối tới Database thông qua hostname `db-server`.

Kết quả ping: 2 gói gửi, 2 gói nhận, 0% packet loss.

### 5.2. Named Volume và tính bền vững dữ liệu

Volume `db-data` được gắn vào thư mục dữ liệu PostgreSQL.

Sau khi xóa container Database cũ và tạo lại container `db-server` với volume cũ, truy vấn bảng `students` vẫn trả về 4 bản ghi có ID 1, 34, 67 và 100.

Kết quả chứng minh dữ liệu được lưu trong Named Volume thay vì chỉ phụ thuộc vào container.

### 5.3. Backend API

Endpoint kiểm tra trạng thái:

```text
GET http://localhost:8080/health
```

Kết quả:

```json
{"status":"UP","database":"db-server"}
```

Endpoint lấy danh sách sinh viên:

```text
GET http://localhost:8080/students
```

API trả về danh sách dữ liệu từ PostgreSQL thành công.

### 5.4. Trạng thái tài nguyên

Sau khi script hoàn tất:

- Network `app-net` tồn tại.
- Volume `db-data` tồn tại.
- Container `db-server` đang chạy.
- Container `app-container` đang chạy.
- Backend được ánh xạ cổng máy chủ `8080` tới cổng container `3000`.

## 6. Lệnh kiểm tra thủ công

```bash
docker network ls
docker network inspect app-net

docker volume ls
docker volume inspect db-data

docker ps

docker exec app-container ping -c 2 db-server

curl http://localhost:8080/health
curl http://localhost:8080/students

docker exec db-server psql -U appuser -d appdb \
  -c "SELECT * FROM students ORDER BY id;"
```

