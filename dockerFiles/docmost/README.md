# Docmost (Docker Compose)

本目录用于启动 `Docmost + Postgres + Redis`,配置与数据均挂载到本目录下的 `./volumes/`。

## 目录结构

```
docmost/
├── docker-compose.yml
├── .env                     # 容器名 / 端口 / 账号 / 网络名等变量
└── volumes/
    ├── storage/             # Docmost 应用存储
    ├── db/                  # Postgres 数据
    └── redis/               # Redis 数据
```

## 配置变量(`.env`)

| 变量 | 默认值 | 说明 |
| --- | --- | --- |
| `DOCMOST_APP_CONTAINER_NAME` | `docmost-app` | 应用容器名 |
| `DOCMOST_DB_CONTAINER_NAME` | `docmost-db` | Postgres 容器名 |
| `DOCMOST_REDIS_CONTAINER_NAME` | `docmost-redis` | Redis 容器名 |
| `DOCMOST_APP_URL` | `http://localhost:13001` | 应用对外访问地址 |
| `DOCMOST_APP_SECRET` | (随机串) | 应用密钥 |
| `DOCMOST_PORT` | `13001` | 宿主机端口(映射到容器 3000) |
| `DOCMOST_DB_NAME` | `docmost` | Postgres 数据库名 |
| `DOCMOST_DB_USER` | `docmost` | Postgres 用户 |
| `DOCMOST_DB_PASSWORD` | (随机串) | Postgres 密码 |
| `DOCMOST_DATABASE_URL` | `postgresql://…@docmost-db:5432/…` | 应用连库串,主机名为 db 服务名 |
| `DOCMOST_REDIS_URL` | `redis://docmost-redis:6379` | 应用连 Redis 串,主机名为 redis 服务名 |
| `DOCMOST_NETWORK_NAME` | `devbox-shared-net` | 共享网络名,多个应用互访时填相同值 |

> `.env` 与 `docker-compose.yml` 同目录,Compose 会自动加载,无需再加 `--env-file`。
> `DOCMOST_DATABASE_URL` / `DOCMOST_REDIS_URL` 里的主机名是 **compose 服务名**(`docmost-db` / `docmost-redis`),即使改了容器名也不受影响。

## 使用

以下命令均在**本目录下**执行:

```bash
# 启动(后台)
docker compose up -d

# 查看状态 / 应用日志
docker compose ps
docker compose logs -f docmost-app

# 停止 / 停止并移除容器
docker compose stop
docker compose down
```

## 升级 Docmost

升级前先备份,再拉镜像重建,最后验活。

### 1) 升级前备份

```bash
mkdir -p ./backup
cp -r ./volumes "./backup/docmost-$(date +%Y%m%d-%H%M%S)"
```

备份内容包含:

- 数据库数据:`./volumes/db`
- Redis 数据:`./volumes/redis`
- Docmost 存储:`./volumes/storage`

### 2) 执行升级

```bash
docker compose pull docmost-app
docker compose up -d docmost-app
```

### 3) 升级后验证

```bash
docker compose ps
docker compose logs --tail=200 docmost-app
```

日志里应看到数据库连接成功、migration 成功、应用 started。

## 回滚

当升级后出现不可接受问题时,按下面流程回滚。

### 1) 停止服务

```bash
docker compose down
```

### 2) 恢复备份数据

将 `<backup-dir>` 替换为你要恢复的备份目录,例如:`./backup/docmost-20260327-130000`。

```bash
rm -rf ./volumes
cp -r "<backup-dir>" ./volumes
```

### 3) 启动并验证

```bash
docker compose up -d
docker compose logs --tail=200 docmost-app
```

## 访问地址

- 默认:`http://localhost:13001`
- 实际端口由 `.env` 中 `DOCMOST_PORT` 决定

## 跨容器互访

多个应用的 `.env` 里把 `DOCMOST_NETWORK_NAME` 填成与其它应用**同一个值**(默认 `devbox-shared-net`),即加入同一张网络,容器之间可直接用**容器名/服务名**访问。谁先 `up` 谁创建该网络,其余复用。

## 常见问题

- 若日志出现 `variable is not set`,确认在本目录下执行、且 `.env` 存在。
- 若 `docmost-app` 一直重启,先看日志是否为环境变量校验失败:
  ```bash
  docker compose logs --tail=200 docmost-app
  ```
- 若数据库连接失败,确认 `.env` 中 `DOCMOST_DATABASE_URL` / `DOCMOST_DB_NAME` / `DOCMOST_DB_USER` / `DOCMOST_DB_PASSWORD` 一致。
- 若端口访问不到,先确认端口映射和服务状态:`docker compose ps`。
