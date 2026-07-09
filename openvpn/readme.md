# OpenVPN 安装与卸载

通过系统包管理器安装 OpenVPN（默认版本），支持 Ubuntu / Debian / Rocky Linux / CentOS。

> OpenVPN 服务端是 Linux 组件。macOS / Windows 请安装官方客户端（Tunnelblick、OpenVPN Connect / GUI）。
> RHEL 系（dnf/yum）的 `openvpn` 包位于 **EPEL**，`install.sh` 会自动先启用 EPEL 再安装。

## 安装

```bash
# 本地
sudo ./install.sh

# 远程（无需 clone）
curl -fsSL https://raw.githubusercontent.com/qq61538187/ops-toolkit/main/openvpn/install.sh | sudo bash
```

CentOS 8 已 EOL（官方源迁到 vault.centos.org），可让脚本自动切换后再装：

```bash
sudo FIX_EOL_REPO=1 ./install.sh
```

安装完成后验证：

```bash
openvpn --version
```

## 服务端最小配置（示例）

安装脚本只负责装好 `openvpn` 二进制，PKI 与配置需按需生成。下面给一个基于 easy-rsa 的常见流程。

**1) 安装 easy-rsa 并初始化 PKI：**

```bash
# Debian/Ubuntu
sudo apt-get install -y easy-rsa
# RHEL 系（EPEL）
sudo dnf install -y easy-rsa   # 或 yum

make-cadir ~/openvpn-ca && cd ~/openvpn-ca
./easyrsa init-pki
./easyrsa build-ca nopass              # 生成 CA
./easyrsa gen-req server nopass        # 服务端请求
./easyrsa sign-req server server       # 用 CA 签发服务端证书
./easyrsa gen-dh                       # Diffie-Hellman 参数
openvpn --genkey secret ta.key         # tls-auth 密钥
```

**2) 拷贝证书/密钥到 /etc/openvpn：**

```bash
sudo cp pki/ca.crt pki/issued/server.crt pki/private/server.key \
        pki/dh.pem ta.key /etc/openvpn/
```

**3) 写 `/etc/openvpn/server.conf`（最小示例）：**

```conf
port 1194
proto udp
dev tun
ca   ca.crt
cert server.crt
key  server.key
dh   dh.pem
tls-auth ta.key 0
server 10.8.0.0 255.255.255.0
push "redirect-gateway def1 bypass-dhcp"
push "dhcp-option DNS 1.1.1.1"
keepalive 10 120
cipher AES-256-GCM
persist-key
persist-tun
user  nobody
group nogroup            # RHEL 系用 nobody
verb 3
```

**4) 开启内核转发并放行流量（示例，按实际网卡/防火墙调整）：**

```bash
echo 'net.ipv4.ip_forward=1' | sudo tee /etc/sysctl.d/99-openvpn.conf
sudo sysctl --system
# NAT（出口网卡假设为 eth0）
sudo iptables -t nat -A POSTROUTING -s 10.8.0.0/24 -o eth0 -j MASQUERADE
```

**5) 启动服务（systemd 模板单元，配置名即实例名）：**

```bash
sudo systemctl enable --now openvpn-server@server   # 对应 /etc/openvpn/server/server.conf
# 若把 server.conf 放在 /etc/openvpn/ 下，则用：
sudo systemctl enable --now openvpn@server
sudo systemctl status openvpn-server@server
```

> 说明：新版 systemd 单元读取 `/etc/openvpn/server/*.conf`（`openvpn-server@`）或
> `/etc/openvpn/client/*.conf`（`openvpn-client@`）。放置目录与单元名要对应。

## 客户端

用 easy-rsa 为每个客户端签发证书（`gen-req` / `sign-req client`），再写 `client.ovpn`：

```conf
client
dev tun
proto udp
remote <服务器公网IP> 1194
resolv-retry infinite
nobind
persist-key
persist-tun
remote-cert-tls server
tls-auth ta.key 1
cipher AES-256-GCM
verb 3
# 下面可用 <ca>/<cert>/<key> 内联证书，或指向文件
ca   ca.crt
cert client1.crt
key  client1.key
```

把 `client.ovpn` 导入客户端（OpenVPN Connect / Tunnelblick / network-manager-openvpn）即可连接。

## 常见运维操作

以下命令假设 easy-rsa 目录在 `~/openvpn-ca`，服务端配置在 `/etc/openvpn/server/server.conf`（systemd 单元 `openvpn-server@server`）。请按实际路径调整。

### 添加一个用户（签发客户端证书）

```bash
cd ~/openvpn-ca
./easyrsa gen-req  client1 nopass     # 生成 client1 的私钥与请求（nopass=不设密码）
./easyrsa sign-req client client1     # 用 CA 签发（类型必须是 client）
```

生成物：`pki/private/client1.key`、`pki/issued/client1.crt`。把它们连同 `pki/ca.crt`、`ta.key` 交给客户端，填进上文的 `client.ovpn` 即可。**新增用户无需重启服务端**。

> 批量/自动化时，可写个脚本循环 `gen-req` + `sign-req`，再用 `sed` 把证书内联进 `.ovpn` 模板下发。

### 吊销一个用户（禁止其再连接）

```bash
cd ~/openvpn-ca
./easyrsa revoke client1              # 吊销证书
./easyrsa gen-crl                     # 重新生成吊销列表 CRL
sudo cp pki/crl.pem /etc/openvpn/     # 覆盖服务端使用的 CRL
```

在 `server.conf` 里启用 CRL 校验（只需加一次，之后每次更新 CRL 生效）：

```conf
crl-verify crl.pem
```

改完 `server.conf` 需重启：`sudo systemctl restart openvpn-server@server`。已在线的该用户会在下次重连时被拒。

### 给用户分配固定 IP（client-config-dir）

**1) 在 `server.conf` 打开按客户端配置目录：**

```conf
client-config-dir /etc/openvpn/ccd
```

**2) 建目录，为该用户创建一个「与证书 CN 同名」的文件：**

```bash
sudo mkdir -p /etc/openvpn/ccd
# 文件名 = 客户端证书的 Common Name（上面签发时的 client1）
echo 'ifconfig-push 10.8.0.50 255.255.255.0' | sudo tee /etc/openvpn/ccd/client1
```

之后 `client1` 每次连上都会拿到 `10.8.0.50`。

> 要点：
> - 固定 IP 要落在 `server 10.8.0.0 255.255.255.0` 网段内，且**避开 DHCP 动态分配区间**，建议用靠后的地址（如 `.50` 起）。
> - 文件名必须与证书 CN 完全一致，否则不生效。
> - 改 `ccd/*` 无需重启服务，客户端重连即生效；但**新增 `client-config-dir` 这一行**需要重启一次。

### 通过某用户下发额外路由 / DNS

同样写在该用户的 `ccd/<CN>` 文件里，例如只给某人推送一条内网路由：

```bash
echo 'push "route 192.168.10.0 255.255.255.0"' | sudo tee -a /etc/openvpn/ccd/client1
```

### 查看在线用户 / 状态

在 `server.conf` 里开启状态文件：

```conf
status /var/log/openvpn/status.log
```

然后查看（含每个客户端的虚拟 IP、真实 IP、收发流量）：

```bash
sudo cat /var/log/openvpn/status.log
```

### 服务的启停与日志

```bash
sudo systemctl restart openvpn-server@server   # 重启（改了 server.conf 后）
sudo systemctl status  openvpn-server@server   # 运行状态
journalctl -u openvpn-server@server -f         # 实时日志（握手/连接问题排查）
```

### 排查连不上的常见方向

- 服务器防火墙 / 云安全组是否放行 `1194/udp`（或你改的端口协议）。
- 内核转发是否开启：`sysctl net.ipv4.ip_forward` 应为 `1`。
- NAT 规则是否生效：`sudo iptables -t nat -L POSTROUTING -n`（重启后 iptables 规则会丢，需持久化或用 firewalld/nftables）。
- 时间不同步或证书过期会导致 TLS 握手失败，`journalctl` 里能看到 `VERIFY ERROR`。

## 卸载

```bash
# 卸载软件包，保留 /etc/openvpn（证书/密钥/配置）
sudo ./uninstall.sh

# apt：连同包配置一起清理
sudo PURGE=1 ./uninstall.sh

# 额外删除 /etc/openvpn（含证书/密钥，谨慎！）
sudo PURGE_CONFIG=1 ./uninstall.sh

# RHEL 系：连同 EPEL 一起移除
sudo REMOVE_EPEL=1 ./uninstall.sh
```

卸载脚本会先 `systemctl disable --now` 停掉正在运行的 `openvpn-server@` / `openvpn-client@` / `openvpn@` 单元，再移除软件包。默认**不**删除 `/etc/openvpn`，避免误删证书；确认不再需要时用 `PURGE_CONFIG=1` 显式清理。
