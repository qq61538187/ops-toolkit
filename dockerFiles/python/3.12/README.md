# Python 3.12 (Docker Compose)

基于 `python:3.12` 的开发容器,工作区与数据均挂载到本目录下的 `./volumes/python/`。

## 目录结构

```
3.12/
├── docker-compose.yml
├── .env                      # 容器名 / 网络名等变量
└── volumes/python/
    ├── workspace/            # 工作目录(挂载为容器 /workspace)
    ├── data/                 # 持久化数据
    └── backup/               # 备份目录
```

## 配置变量(`.env`)

| 变量 | 默认值 | 说明 |
| --- | --- | --- |
| `PYTHON_CONTAINER_NAME` | `mac-devbox-python312` | 容器名,多实例部署时区分 |
| `PYTHON_NETWORK_NAME` | `devbox-shared-net` | 共享网络名,多个应用互访时填相同值 |

## 使用

```bash
# 启动(后台)
docker compose up -d

# 查看状态 / 日志
docker compose ps
docker compose logs -f

# 进入容器交互 shell
docker compose exec python bash

# 在容器内执行 Python 脚本
docker compose exec python python /workspace/your_script.py

# 停止 / 停止并移除容器
docker compose stop
docker compose down
```

> 直接编辑宿主机 `./volumes/python/workspace/` 下的文件即可在容器内生效;`data/` 与 `backup/` 为可写持久化目录。

## 跨容器互访

多个 python / 应用的 `.env` 里把 `PYTHON_NETWORK_NAME` 填成**同一个值**,即加入同一张网络,容器之间可直接用**容器名**访问:

```python
# 在另一个容器内通过 HTTP 访问 nginx 示例
# requests.get("http://mac-devbox-nginx:80")
```

谁先 `up` 谁创建该网络,其余复用。

## 常见问题

- **容器启动后无法写入 workspace**:确认 `volumes/python/workspace/` 目录存在(仓库已内置 `.gitkeep`)。
- **与 nginx 互通**:两边 `.env` 的 `*_NETWORK_NAME` 均设为 `devbox-shared-net`,启动后用容器名互访。
