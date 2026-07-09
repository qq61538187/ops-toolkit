# Verdaccio (Docker Compose)

基于 `verdaccio/verdaccio:5` 的私有 npm 仓库,配置与数据均挂载到本目录下的 `./volumes/`。

## 目录结构

```
verdaccio/
├── docker-compose.yml
├── .env                     # 端口 / 容器名 / 网络名等变量
└── volumes/
    ├── conf/config.yaml     # 主配置
    ├── plugins/             # 插件
    ├── storage/             # 包存储
    └── backup/              # 备份
```

## 配置变量(`.env`)

| 变量 | 默认值 | 说明 |
| --- | --- | --- |
| `VERDACCIO_CONTAINER_NAME` | `mac-devbox-verdaccio` | 容器名,多实例部署时区分 |
| `VERDACCIO_PORT` | `12873` | 宿主机端口(映射到容器 4873) |
| `VERDACCIO_NETWORK_NAME` | `devbox-shared-net` | 共享网络名,多个应用互访时填相同值 |

> `.env` 与 `docker-compose.yml` 同目录,Compose 会自动加载,无需再加 `--env-file`。

## 使用

以下命令均在**本目录下**执行:

```bash
# 启动(后台)
docker compose up -d

# 查看状态 / 日志
docker compose ps
docker compose logs -f

# 停止 / 停止并移除容器
docker compose stop
docker compose down
```

访问地址:`http://localhost:12873`(实际端口由 `.env` 中 `VERDACCIO_PORT` 决定)。

## 跨容器互访

多个应用的 `.env` 里把 `VERDACCIO_NETWORK_NAME` 填成与其它应用**同一个值**(默认 `devbox-shared-net`),即加入同一张网络,容器之间可直接用**容器名**访问。谁先 `up` 谁创建该网络,其余复用。

## 常见问题

- **启动即退出、`config.yaml` 变成目录**:`config.yaml` 是文件挂载,首次 `up` 前需确保 `./volumes/conf/config.yaml` 是已存在的文件,否则 Docker 会误建成目录。
- **端口被占用**:修改 `.env` 中的 `VERDACCIO_PORT` 后重新 `up -d`。
