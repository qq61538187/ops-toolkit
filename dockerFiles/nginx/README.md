# Nginx (Docker Compose)

基于 `nginx:latest` 的容器化部署,配置与数据均挂载到本目录下的 `./volumes/nginx/`。

## 目录结构

```
nginx/
├── docker-compose.yml
├── .env                      # 端口 / 容器名 / 网络名等变量
└── volumes/nginx/
    ├── nginx.conf            # 主配置
    ├── conf.d/               # 站点配置(default/ssl/cache/security)
    ├── html/                 # 站点根目录
    ├── ssl/                  # 证书(nginx-selfsigned.crt/key)
    └── logs/                 # 日志(含 localhost/ 子目录)
```

## 配置变量(`.env`)

| 变量 | 默认值 | 说明 |
| --- | --- | --- |
| `NGINX_CONTAINER_NAME` | `mac-devbox-nginx` | 容器名,多实例部署时区分 |
| `NGINX_HTTP_PORT` | `80` | 宿主机 HTTP 端口 |
| `NGINX_HTTPS_PORT` | `443` | 宿主机 HTTPS 端口 |
| `NGINX_NETWORK_NAME` | `devbox-shared-net` | 共享网络名,多个应用互访时填相同值 |

## 使用

```bash
# 启动(后台)
docker compose up -d

# 查看状态 / 日志
docker compose ps
docker compose logs -f

# 修改 conf.d 或 html 后热加载(无需重启)
docker compose exec nginx nginx -s reload

# 校验配置语法
docker compose exec nginx nginx -t

# 停止 / 停止并移除容器
docker compose stop
docker compose down
```

> 配置类目录以只读(`:ro`)挂载,直接编辑宿主机 `./volumes/nginx/` 下的文件即可生效,`logs/` 为可写。

## 跨容器互访

多个 nginx / 应用的 `.env` 里把 `NGINX_NETWORK_NAME` 填成**同一个值**,即加入同一张网络,容器之间可直接用**容器名**访问:

```nginx
# 在另一个 nginx 中反向代理到本容器
proxy_pass http://mac-devbox-nginx:80;
```

谁先 `up` 谁创建该网络,其余复用。

## 常见问题

- **启动即退出、报错 `open() /var/log/nginx/localhost/error.log failed`**:确认 `volumes/nginx/logs/localhost/` 目录存在(仓库已内置 `.gitkeep`)。
- **端口被占用**:修改 `.env` 中的 `NGINX_HTTP_PORT` / `NGINX_HTTPS_PORT` 后重新 `up -d`。
