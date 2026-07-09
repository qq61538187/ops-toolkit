# Excalidraw Docker 使用说明

本目录为 **Excalidraw 静态前端** 自托管实例，无持久化数据卷；端口见 `EXCALIDRAW_PORT`（默认 13004）。

官方说明：当前自托管**不支持**端到端协作/分享等云端能力，仅本地白板客户端。

## 启动 / 停止

在仓库根目录：

```bash
docker compose --env-file .env -f dockerfiles/excalidraw/docker-compose.yml up -d
docker compose --env-file .env -f dockerfiles/excalidraw/docker-compose.yml down
```

访问：`http://localhost:${EXCALIDRAW_PORT}`

## 参考

- [Docker Hub - excalidraw/excalidraw](https://hub.docker.com/r/excalidraw/excalidraw)
