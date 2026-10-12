#!/bin/bash
set -Eeuo pipefail

NETWORK="app-net"
VOLUME="db-data"
DB_CONTAINER="db-server"
APP_CONTAINER="app-container"
DB_IMAGE="postgres:15-alpine"
APP_IMAGE="homework-backend:v1"

DB_NAME="appdb"
DB_USER="appuser"
DB_PASSWORD="postgres123"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_DIR="$SCRIPT_DIR/.backend-build"

cd "$SCRIPT_DIR"

echo "===== 1. Tao Custom Bridge Network ====="
docker network inspect "$NETWORK" >/dev/null 2>&1 || 
    docker network create "$NETWORK"
docker network inspect "$NETWORK"

echo "===== 2. Tao Named Volume ====="
docker volume inspect "$VOLUME" >/dev/null 2>&1 || 
    docker volume create "$VOLUME"
docker volume inspect "$VOLUME"

echo "===== 3. Tao ma nguon Backend ====="
mkdir -p "$BUILD_DIR"

cat > "$BUILD_DIR/package.json" <<'EOF'
{
  "name": "homework-backend",
  "version": "1.0.0",
  "private": true,
  "dependencies": {
    "pg": "^8.16.3"
  }
}
EOF

cat > "$BUILD_DIR/server.js" <<'EOF'
const http = require("http");
const { Pool } = require("pg");

const pool = new Pool({
  host: process.env.DB_HOST || "db-server",
  port: Number(process.env.DB_PORT || 5432),
  database: process.env.DB_NAME || "appdb",
  user: process.env.DB_USER || "appuser",
  password: process.env.DB_PASSWORD
});

const server = http.createServer(async (req, res) => {
  res.setHeader("Content-Type", "application/json");

  try {
    if (req.url === "/health") {
      await pool.query("SELECT 1");
      res.writeHead(200);
      res.end(JSON.stringify({
        status: "UP",
        database: process.env.DB_HOST || "db-server"
      }));
      return;
    }

    if (req.url === "/students") {
      const result = await pool.query(
        "SELECT id, name FROM students ORDER BY id"
      );
      res.writeHead(200);
      res.end(JSON.stringify(result.rows));
      return;
    }

    res.writeHead(404);
    res.end(JSON.stringify({ error: "Not found" }));
  } catch (error) {
    res.writeHead(503);
    res.end(JSON.stringify({ error: "Database unavailable" }));
  }
});

server.listen(3000, "0.0.0.0", () => {
  console.log("Backend listening on port 3000");
});
EOF

cat > "$BUILD_DIR/Dockerfile" <<'EOF'
FROM node:20-alpine
RUN apk add --no-cache iputils postgresql-client
WORKDIR /app
COPY package.json ./
RUN npm install --omit=dev
COPY server.js ./
EXPOSE 3000
CMD ["node", "server.js"]
EOF

echo "===== 4. Build Backend Image ====="
docker build -t "$APP_IMAGE" "$BUILD_DIR"

echo "===== 5. Khoi chay PostgreSQL ====="
docker rm -f "$APP_CONTAINER" "$DB_CONTAINER" >/dev/null 2>&1 || true


docker run -d \
    --name "$DB_CONTAINER" \
    --network "$NETWORK" \
    --network-alias db-server \
    -e POSTGRES_DB="$DB_NAME" \
    -e POSTGRES_USER="$DB_USER" \
    -e POSTGRES_PASSWORD="$DB_PASSWORD" \
    -v "$VOLUME":/var/lib/postgresql/data \
    "$DB_IMAGE"

echo "===== 6. Cho PostgreSQL san sang ====="

READY=0

for i in $(seq 1 30); do
    if docker exec db-server pg_isready -U appuser -d appdb; then
        READY=1
        break
    fi
    sleep 2
done

if [ "$READY" -ne 1 ]; then
    echo "Loi: PostgreSQL chua san sang."
    docker logs db-server
    exit 1
fi


echo "===== 7. Khoi chay Backend ====="

docker run -d \
  --name "$APP_CONTAINER" \
  --network "$NETWORK" \
  -p 8080:3000 \
  -e DB_HOST=db-server \
  -e DB_PORT=5432 \
  -e DB_NAME="$DB_NAME" \
  -e DB_USER="$DB_USER" \
  -e DB_PASSWORD="$DB_PASSWORD" \
  "$APP_IMAGE"


echo "===== 8. Cho Backend khoi dong ====="
sleep 3

echo "===== 9. Kiem tra DNS noi bo ====="
docker exec "$APP_CONTAINER" ping -c 2 db-server


echo "===== 10. Tao bang va them du lieu ====="

docker exec "$DB_CONTAINER" psql \
    -U "$DB_USER" -d "$DB_NAME" -v ON_ERROR_STOP=1 \
    -c "CREATE TABLE IF NOT EXISTS students (
        id SERIAL PRIMARY KEY,
        name VARCHAR(100) NOT NULL
    );"

docker exec "$DB_CONTAINER" psql \
    -U "$DB_USER" -d "$DB_NAME" -v ON_ERROR_STOP=1 \
    -c "INSERT INTO students (name)
        VALUES ('Student Persistence Test');"



echo "===== 11. Kiem tra Backend API ====="

curl --fail --retry 10 --retry-delay 2 --retry-connrefused \
    http://localhost:8080/health
echo

curl --fail http://localhost:8080/students
echo


echo "===== 12. Xoa cung Container Database ====="
docker rm -f "$DB_CONTAINER"


echo "===== 13. Tao lai Database voi Volume cu ====="

docker run -d \
    --name "$DB_CONTAINER" \
    --network "$NETWORK" \
    --network-alias db-server \
    -e POSTGRES_DB="$DB_NAME" \
    -e POSTGRES_USER="$DB_USER" \
    -e POSTGRES_PASSWORD="$DB_PASSWORD" \
    -v "$VOLUME":/var/lib/postgresql/data \
    "$DB_IMAGE"


echo "===== 14. Cho PostgreSQL san sang ====="

READY=0
for i in $(seq 1 30); do
    if docker exec "$DB_CONTAINER" pg_isready -U "$DB_USER" -d "$DB_NAME"; then
        READY=1
        break
    fi
    sleep 2
done

if [ "$READY" -ne 1 ]; then
    echo "Loi: PostgreSQL chua san sang sau khi khoi phuc."
    docker logs "$DB_CONTAINER"
    exit 1
fi

echo "===== 15. Xac minh du lieu sau khi khoi phuc ====="

docker exec "$DB_CONTAINER" psql \
    -U "$DB_USER" -d "$DB_NAME" -v ON_ERROR_STOP=1 \
    -c "SELECT * FROM students ORDER BY id;"

echo "===== 16. Khoi dong lai Backend neu can ====="

if [ "$(docker inspect -f '{{.State.Running}}' "$APP_CONTAINER" 2>/dev/null)" != "true" ]; then
    docker start "$APP_CONTAINER"
fi

echo "===== 17. Kiem tra DNS noi bo ====="
docker exec "$APP_CONTAINER" ping -c 2 db-server

echo "===== 18. Kiem tra Backend API ====="
curl --fail --retry 10 --retry-delay 2 --retry-connrefused \
    http://localhost:8080/health
echo

curl --fail --retry 5 --retry-delay 2 \
    http://localhost:8080/students
echo

echo "===== 19. Kiem tra Network va Volume ====="
docker network ls | grep "$NETWORK"
docker volume ls | grep "$VOLUME"
docker ps

echo "===== HOAN THANH ====="
echo "Da kiem tra DNS, Backend API va du lieu PostgreSQL sau khi tao lai container."
echo "Backend API: http://localhost:8080/health"
echo "Students API: http://localhost:8080/students"
