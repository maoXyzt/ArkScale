# ArkScale 实施设计

> 状态：实施前设计（尚无可构建源码）
>
> 核对日期：2026-08-02
>
> 目标：在 HarmonyOS NEXT API 22+ 上实现一个最小、可自用的 Tailscale 全设备 VPN 客户端。

## 1. 结论与边界

方案在架构上可行，但尚未被公开项目端到端证明。现有证据只分别覆盖了以下部分：

- HarmonyOS/OpenHarmony 提供三方 VPN API，可创建 TUN，并从 API 22 起用 `protectProcessNet()` 保护当前进程之后创建的 socket；Native 代码可直接读写 TUN FD。
- OpenHarmony-SIG 的 Go 分支提供 `GOOS=openharmony`、`GOARCH=arm64`、cgo、`c-archive` 和 `c-shared` 支持。
- ClashBox 的源码与 HAP Release 提供了商业 HarmonyOS NEXT 上“Go 共享库 + VPN Ability + TUN + 逐 socket protect”的相邻真机证据，但其网络核心不是 Tailscale。
- Tailscale Android 客户端证明了移动端可用 `wgengine`、可替换 TUN、路由/DNS 回调和逐 socket 保护来实现系统 VPN。

这些证据不能替代 ArkScale 在目标 HarmonyOS NEXT 手机上的 PoC。项目按门禁推进：前一阶段未通过，不进入后一阶段。

### 1.1 首个可交付版本

首版只包含：

- arm64 真机；
- 交互式登录、登出和状态持久化；
- tailnet 节点 IPv4/IPv6 访问；
- MagicDNS；
- DERP 和直连；
- Wi-Fi/蜂窝切换；
- 进程被终止后的安全清理与重新连接。

暂不包含复杂 UI、Taildrop、出口节点、发布子网路由、按应用分流和商店上架适配。

### 1.2 不可作为实现前提的说法

- 不能用上游 Go 的 `GOOS=linux` 直接交叉编译并假定可运行。必须使用固定的 OpenHarmony-SIG Go 分支。
- 不能把 `tailscale/libtailscale` 当成全设备 TUN 引擎。它公开的是 `tsnet` socket API。
- 不能硬编码 Tailscale 地址、`100.64.0.0/10` 或 `100.100.100.100`；地址、路由、DNS 和 MTU 必须来自 backend。
- 三方 VPN 基线不申请 `ohos.permission.MANAGE_VPN`，也不把 ACL/系统签名作为前置条件。基线权限为 `ohos.permission.INTERNET` 加系统 VPN 用户授权。
- 不逐包穿越 ArkTS/Node-API；数据包由 Go 直接读写 TUN FD。
- API 22+ 首版不实现逐 socket protect 回调；只有 P2 证明进程级保护不可用时才回退。

## 2. 固定基线

所有依赖先固定到提交，升级必须重新走本设计的 P0–P4 验收。

| 组件 | 固定基线 | 使用说明 |
| --- | --- | --- |
| HarmonyOS | compatible SDK API 22，compile SDK API 24 | API 22 提供 `protectProcessNet()`；商业版目标机仍需独立验证。 |
| OpenHarmony | 5.0.0 Release+ 作为开源对照 | Go SIG 提案给出的最低验证基线；不等同于商业 HarmonyOS NEXT。 |
| Go | `ohos_golang_go` `release-branch.go1.24`，commit `2d8b23f6923100d8c90d8add9299da2c9d032a20` | 仓库 `VERSION` 为 `go1.24.5`；目标为 `openharmony/arm64`。这是补丁分支，不是上游 Go 官方支持。 |
| Tailscale | v1.82.5，commit `e4d64c6faf827a308ec20b39651225178e6743c0` | 已通过 P0/P3 与目标真机门禁的冻结基线；升级必须重跑验收。 |
| P0 builder | `golang:1.24.5-bookworm@sha256:9aba206b3974f93f7056304c991c9cc1f843c939159d9305571ab9766c9ccdf6` | Docker Official Images 的 linux/amd64 manifest；不依赖可变标签。 |
| 构建主机 | Linux x86_64 | 与 OpenHarmony-SIG Go 已公开的交叉编译验证环境一致。DevEco/HAP 打包可按 SDK 支持的平台另行执行。 |
| 目标 ABI | `arm64-v8a` / `aarch64-linux-ohos` | 首版不做 x86_64 模拟器和 32 位。 |

上游 Go 的支持列表没有 OpenHarmony；SIG 分支的目标名是 `GOOS=openharmony`。该分支为了复用 Linux 生态，会使 Linux build tag 成立，并让 `runtime.GOOS` 报告 `linux`，平台专用判断应使用该分支提供的 `runtime.IsOpenharmony`。这也意味着 Tailscale 中所有 Linux 专用路径都必须逐项审计，不能默认适用。

## 3. 系统架构

```text
EntryAbility / ArkUI
        │ 启停、登录 URL、状态
        ▼
VpnExtensionAbility ───── VpnConnection.create/protect/destroy
        │ 控制事件、配置、FD
        ▼
Node-API C++ addon ────── dup(TUN FD)、异步事件泵、线程切换
        │ 稳定 C ABI
        ▼
libarkscale_engine.so ─── Tailscale mobile backend / wgengine
        │
        └──────────────── 直接 read/write duplicated TUN FD
```

### 3.1 职责

- ArkUI：只负责用户操作和展示；不持有长期网络状态。
- `VpnExtensionAbility`：持有 `VpnConnection`，处理用户授权、进程级保护、TUN 创建/重建和网络变化。
- Node-API：提供非阻塞 ArkTS API；管理 C 字符串和 FD 所有权；把 Go 事件安全投递到 ArkTS 线程。
- Go engine：复用 Tailscale 控制面、WireGuard、DERP、netstack/wgengine 和状态机；产出 VPN 配置与保护请求。

Extension、Node-API addon 和 Go 动态库必须在同一进程内运行。P2 要记录三层 PID 并验证；不要在 `module.json5` 中额外拆分进程。

## 4. 仓库落地结构

实现时使用以下最小结构：

```text
ArkScale/
├── entry/
│   └── src/main/
│       ├── ets/
│       │   ├── entryability/EntryAbility.ets
│       │   └── vpnextension/ArkScaleVpnExtension.ets
│       ├── cpp/
│       │   ├── CMakeLists.txt
│       │   ├── napi_init.cpp
│       │   └── libs/arm64-v8a/
│       │       ├── libarkscale_engine.so
│       │       └── libarkscale_engine.h
│       └── module.json5
├── engine/
│   ├── go.mod
│   ├── cmd/arkscale/main.go
│   └── internal/...
├── patches/tailscale/
├── scripts/ohos-clang
├── scripts/ohos-clang++
├── tests/
└── third_party/                 # 不提交完整源码；由锁定脚本拉取
```

## 5. Go 与 Tailscale 适配

### 5.1 不能直接采用官方 C library

`tailscale/libtailscale` 的 C ABI 主要暴露 `tsnet` 的 listen/dial 等用户态 socket 能力，不接收系统 TUN FD，也不负责全设备路由。ArkScale 应参照 `tailscale-android/libtailscale`：

- 用 `wgengine.NewUserspaceEngine`；
- 用一个同时实现 `router.Router` 和 `dns.OSConfigurator` 的 facade，把路由/DNS 配置作为事件上送；
- 用可替换 TUN 设备承接 HarmonyOS 重建后的 FD；
- 在启动 backend、创建任何外层 socket 前完成平台 `protectProcessNet()`；
- 底层网络变化后通知 netmon/backend 重绑。

### 5.2 必做源码适配

OpenHarmony-SIG Go 会启用 Linux build tag，因此至少要审计并形成可复查补丁：

1. `net/netns`
   - 排除 OpenHarmony 进入 Linux 的 `SO_MARK` / `SO_BINDTODEVICE` 路径；
   - 新增最小 OpenHarmony 平台文件，socket control 不再做逐 FD 保护；
   - engine 只允许在 ArkTS 确认 `protectProcessNet()` 成功后启动；失败时不启动 Go；
   - 网络切换仍通知 backend 重绑，但重建 socket 会自动继承进程级保护。
2. `net/netmon`
   - 排除 OpenHarmony 使用 Linux netlink 实现；
   - 先启用通用 polling 路径；
   - ArkTS 监听默认网络/能力变化后，额外调用 `arkscale_network_changed()`。
3. router 与 DNS
   - 不执行 Linux iptables、netlink、`resolv.conf` 等系统配置；
   - 把 `router.Config` 与 DNS manager 的配置转换为平台无关事件，由 `VpnExtensionAbility` 创建或重建 TUN。
4. syscall 与运行时路径
   - 搜索 `//go:build linux`、`runtime.GOOS == "linux"`、`/proc`、netlink、iptables、systemd、Unix namespace；
   - 每个命中在 `patches/tailscale/README.md` 记录“采用、排除、替换或已测试无需修改”。

P3 的硬门槛是运行时没有进入 Linux router/netfilter、Linux netns 或 Linux netlink 路径，而不只是“编译通过”。

`engine/go.mod` 使用 `module` 管理 ArkScale wrapper，并把 `tailscale.com` 固定替换到本地已 checkout、已应用补丁的源码；不能在构建时临时拉取浮动版本：

```go
module arkscale/engine

go 1.24

require tailscale.com v1.82.5

replace tailscale.com => ../third_party/tailscale
```

若项目将来需要发布 Go module，再把本地 module path 换成真实地址。CI 同时校验 `third_party/tailscale` 的 HEAD 是本设计锁定的 commit。

## 6. C ABI 与 Node-API 契约

Go 动态库只导出固定、可版本化的 C ABI：

```c
int arkscale_start(const char *config_json);
int arkscale_next_event(char **json, size_t *len, uint32_t timeout_ms);
void arkscale_free(void *ptr);
int arkscale_set_tun(int dup_fd, uint64_t generation);
void arkscale_network_changed(void);
int arkscale_logout(void);
int arkscale_stop(void);
```

约束：

- `start`、`set_tun`、`logout`、`stop` 必须幂等或返回明确状态码；`stop` 保留身份，`logout` 等待控制面确认后删除当前 profile。
- `next_event` 返回的内存由 Go/C 分配，只能用 `arkscale_free` 释放。
- Node-API 开一个事件泵线程调用 `next_event`；用 thread-safe function 把 JSON 事件投递到 ArkTS，不从 Go 线程直接调用 ArkTS。
- ArkTS 暴露 `start(options): Promise<void>`、`stop(): Promise<void>`、`setTun(fd, generation)`、`networkChanged()` 和 `subscribe(listener)`。
- 所有耗时调用用 Node-API async work；不能阻塞 Ability 主线程。
- 配置与事件都带 `schemaVersion`；未知版本拒绝启动。

最小事件集合：

```json
{"type":"state","state":"needs-login|starting|running|stopped|error"}
{"type":"login-url","url":"https://login.tailscale.com/..."}
{"type":"vpn-config","generation":1,"localAddrs":[],"routes":[],"localRoutes":[],"nameservers":[],"searchDomains":[],"mtu":1280}
{"type":"health","severity":"warning|error","message":"..."}
```

日志事件必须脱敏，不输出 auth key、节点私钥、完整控制面响应或可复用登录 URL。

## 7. VPN 配置映射

`addresses` 是必填项，因此 engine 未给出至少一个本机 Tailscale 地址前不能调用 `VpnConnection.create()`。

API 22 的配置结构应由 backend 事件动态构造：

```ts
const config: vpnExtension.VpnConfig = {
  addresses: model.localAddrs.map(addr => ({
    address: { address: addr.ip, family: addr.family },
    prefixLength: addr.prefixLength
  })),
  routes: model.effectiveRoutes.map(route => ({
    interface: 'vpn-tun',
    destination: {
      address: { address: route.ip, family: route.family },
      prefixLength: route.prefixLength
    },
    gateway: {
      address: route.family === 1 ? '0.0.0.0' : '',
      family: route.family
    },
    hasGateway: false,
    isDefaultRoute: route.prefixLength === 0
  })),
  dnsAddresses: model.nameservers,
  searchDomains: model.searchDomains,
  mtu: model.mtu,
  isIPv4Accepted: model.localAddrs.some(addr => addr.family === 1),
  isIPv6Accepted: model.localAddrs.some(addr => addr.family === 2),
  isBlocking: false
};
```

`hasGateway=false` 时 IPv6 的 `gateway.address` 必须留空。目标 HarmonyOS 版本会把非空的 `::` 继续作为 next-hop 交给底层路由，导致 Tailscale ULA 路由返回 `ENETUNREACH`。

其中 HarmonyOS 的 `family` 取值为 IPv4 `1`、IPv6 `2`。实现时还要：

- 对 route 数量做上限检查（API 文档上限为 1024）；
- 对 CIDR、DNS、MTU 和空数组做严格校验；
- `trustedApplications` 与 `blockedApplications` 不同时设置；
- 明确区分 tailnet 路由、子网路由和出口节点默认路由；
- 首版先按 Tailscale Android `ranges_calc` 的方法计算 `effectiveRoutes = Routes - LocalRoutes`；只有目标 SDK 与真机确认 `RouteInfo.isExcludedRoute` 可用后，才改为显式排除路由；
- 不把空 `routes` 当成“无路由”。OpenHarmony 服务实现会按启用的 IP 家族补默认路由，可能意外形成全隧道。

## 8. 生命周期与并发

### 8.1 启动

1. UI 调用 `startVpnExtensionAbility`，首次启动由系统展示用户授权。
2. Extension `onCreate` 创建 `VpnConnection`，注册 engine 事件订阅和网络变化监听。
3. `await vpnConnection.protectProcessNet()`；失败则停止，不加载 Go engine。
4. Node-API 启动 Go backend；从此之后创建的外层 socket 继承进程级保护。
5. backend 完成登录和网络图同步，发出 `vpn-config`。
6. Extension 校验 generation 与配置，调用 `create(config)` 获得 TUN FD。
7. Node-API 对 FD 执行 `dup()`，把副本交给 Go；Go 只拥有并关闭副本，原 FD 仍由 `VpnConnection`/系统管理。
8. `set_tun(dupFd, generation)` 成功后状态进入 `running`。

### 8.2 重配置

HarmonyOS API 没有原地更新既有 `VpnConfig` 的接口。收到更新配置时必须串行执行：

1. 合并连续更新，只保留最新 generation；
2. 暂停旧 TUN 的新写入；
3. `destroy()` 旧连接并创建新 TUN；
4. `dup()` 新 FD，调用 `set_tun(newFd, generation)`；
5. Go 的可替换 TUN 切换成功后关闭旧副本并恢复流量。

重建期间的丢包、系统是否允许立即重建，以及 FD 切换时序均是 P2/P3 真机验证项。

### 8.3 停止

停止顺序固定为：

1. 阻止新事件和 protect 请求；
2. `arkscale_stop()` 关闭 backend、事件泵和 Go 持有的重复 FD；
3. `VpnConnection.destroy()`；
4. 注销网络监听和 Node-API callback；
5. 状态置为 `stopped`。

`onDestroy`、用户点击停止、启动失败和进程恢复都走同一条幂等清理路径。平台在应用/IPC 客户端死亡时会销毁 VPN，但应用仍需主动清理，不能据此承诺后台永久存活。

## 9. 权限与 Ability 声明

基线 `module.json5` 只申请普通网络权限并声明 VPN Extension：

```json5
{
  "module": {
    "requestPermissions": [
      { "name": "ohos.permission.INTERNET" }
    ],
    "extensionAbilities": [
      {
        "name": "ArkScaleVpnExtension",
        "srcEntry": "./ets/vpnextension/ArkScaleVpnExtension.ets",
        "type": "vpn",
        "visible": true
      }
    ]
  }
}
```

不要在基线中声明 `ohos.permission.MANAGE_VPN`。它是系统级 VPN 管理权限；三方 VPN 走系统用户授权。若将来某个功能确实调用标注该权限的系统 API，应把它作为独立功能重新论证，而不是扩大首版权限。

## 10. 可复现构建

### 10.1 拉取固定源码

在 Linux x86_64 构建机执行：

```bash
git clone https://gitcode.com/openharmony-sig/ohos_golang_go.git third_party/ohos_golang_go
git -C third_party/ohos_golang_go checkout 2d8b23f6923100d8c90d8add9299da2c9d032a20

git clone https://github.com/tailscale/tailscale.git third_party/tailscale
git -C third_party/tailscale checkout e4d64c6faf827a308ec20b39651225178e6743c0
```

每次构建先校验 `git rev-parse HEAD`。依赖升级单独提交，不使用浮动分支或 `latest`。

### 10.2 构建 Go 工具链

SIG 分支的 `make.bash` 需要 Go 1.22.6 或更高版本作为 bootstrap。示例：

```bash
export ARKSCALE_REPO_ROOT="$PWD"
export ARKSCALE_OHOS_NATIVE=/opt/ohos-sdk/linux/native
export ARKSCALE_GO_ROOT="$ARKSCALE_REPO_ROOT/third_party/ohos_golang_go"
export ARKSCALE_GO_BOOTSTRAP=/opt/go1.24.5

cd "$ARKSCALE_GO_ROOT/src"
GOROOT_BOOTSTRAP="$ARKSCALE_GO_BOOTSTRAP" ./make.bash
```

`scripts/ohos-clang`：

```sh
#!/bin/sh
exec "$ARKSCALE_OHOS_NATIVE/llvm/bin/clang" \
  --target=aarch64-linux-ohos \
  --sysroot="$ARKSCALE_OHOS_NATIVE/sysroot" \
  -fPIC -D__MUSL__=1 "$@"
```

`scripts/ohos-clang++` 同理，编译器替换为 `clang++`。

### 10.3 构建 engine

应用 Tailscale 补丁后，从仓库根目录执行：

```bash
export ARKSCALE_REPO_ROOT="$PWD"
export ARKSCALE_OHOS_NATIVE=/opt/ohos-sdk/linux/native
export ARKSCALE_GO_ROOT="$ARKSCALE_REPO_ROOT/third_party/ohos_golang_go"

cd "$ARKSCALE_REPO_ROOT/engine"
env GOTOOLCHAIN=local \
  GOOS=openharmony GOARCH=arm64 CGO_ENABLED=1 \
  CC="$ARKSCALE_REPO_ROOT/scripts/ohos-clang" \
  CXX="$ARKSCALE_REPO_ROOT/scripts/ohos-clang++" \
  AR="$ARKSCALE_OHOS_NATIVE/llvm/bin/llvm-ar" \
  "$ARKSCALE_GO_ROOT/bin/go" build \
  -buildmode=c-shared -trimpath \
  -o "$ARKSCALE_REPO_ROOT/build/arm64-v8a/libarkscale_engine.so" \
  ./cmd/arkscale
```

该命令是待 P0 验证的目标命令，不代表当前仓库已经构建成功。构建后检查：

```bash
llvm-readelf -h build/arm64-v8a/libarkscale_engine.so
llvm-readelf -d build/arm64-v8a/libarkscale_engine.so
```

验收：ELF64/AArch64；无 `GLIBC_` 依赖；无构建机绝对路径/RPATH；`NEEDED` 仅包含已随 HAP 打包或 HarmonyOS 提供的库。

### 10.4 链接到 Node-API addon

```cmake
add_library(arkscale_engine SHARED IMPORTED)
set_target_properties(arkscale_engine PROPERTIES
  IMPORTED_LOCATION
  ${CMAKE_CURRENT_SOURCE_DIR}/libs/${OHOS_ARCH}/libarkscale_engine.so)

target_link_libraries(entry PUBLIC
  arkscale_engine
  libace_napi.z.so)
```

生成的 `.so` 和 `.h` 一起复制到 `entry/src/main/cpp/libs/arm64-v8a/`，再由 HAP 构建验证实际加载。

## 11. 分阶段实施与验收

### P0：Tailscale 依赖闭包编译

先回答“固定版本到底要改多少”，不开发 UI：

- 用锁定的 Go 与 Tailscale commit 编译最小 backend 包和 C ABI；
- 记录全部 build tag、syscall、`x/sys/unix`、netlink、DNS、文件权限和动态链接错误；
- 所有改动保存为 `patches/tailscale/` 下的可重放补丁并写明原因；
- 生成 arm64 `.so` 与头文件，完整构建命令可在干净 Linux builder 重复。

如果需要大面积 fork，而不是有限的平台 build tag 和接口适配，应暂停并重新评估维护成本。

### P1：Go runtime / c-shared 真机 PoC

实现一个不含 Tailscale 的最小动态库，经 Node-API 加载，验证：

- 导出函数调用、goroutine、channel、GC；
- 应用私有目录文件读写；
- UDP、DNS、TLS；
- 100 次启动/停止；
- 进程退出后无残留线程，内存曲线稳定。

产物：设备型号、HarmonyOS/API/SDK 版本、Go commit、编译命令、HAP、日志和失败复现。任何 runtime、TLS、动态加载或 ABI 问题未解决即停止。

### P2：HarmonyOS VPN 平台 PoC

先在同一目标设备/SDK 上跑官方 VPN 示例，再实现 ArkScale echo tunnel：

- 首次启动出现系统 VPN 授权；
- 不申请 `MANAGE_VPN`；
- `VpnConfig` 的 IPv4/IPv6、路由、DNS 和 MTU 生效；
- Native 对 TUN FD 双向读写；
- 在一次 `protectProcessNet()` 后创建至少 100 个 Go UDP/TCP socket，全部绕过 TUN 且无路由环；
- `dup()` 后的 FD 所有权、destroy/recreate 和异常停止正确；
- Extension、addon、Go 在同一 PID。

### P3：Tailscale backend 与平台隔离

- 使用 P0 的固定 v1.82.5 产物和补丁；
- 接入 `wgengine.NewUserspaceEngine` 与 `ipnlocal.LocalBackend`；
- 自动化扫描 Linux build-tag 路径；
- 运行时证明未进入 iptables/netlink/SO_MARK 等 Linux 专用配置；
- protect hook 的成功、拒绝、超时和重绑测试全部通过。
- 交互式登录，登录 URL 安全展示；
- 状态写入应用私有目录，重启可恢复；
- backend 动态产出地址、路由、DNS、MTU；
- TUN 首建与配置变化后的串行重建通过；
- 无硬编码 Tailscale 地址和 DNS。

### P4：端到端网络

- peer ping 与 TCP；
- 先通过 DERP，再验证可观测的直连；
- MagicDNS；
- Tailscale IPv4 与 IPv6；
- Wi-Fi ↔ 蜂窝切换、断网恢复、socket 重建后全部重新 protect；
- 至少一次控制面路由/DNS 变化后的 TUN 重建。

### P5：稳定性与安全

- 截至 2026-08-04，已修复固定 OpenHarmony-SIG Go 提交中 `net.Interfaces()` 未关闭 IPv4 UDP ioctl socket、未释放 `getifaddrs` 结果的问题。修复后同一真机 30 秒前后 FD `47→46`、RSS `+204 KB`，两次 peer 探针均通过；这不替代 24 小时门禁；
- 24 小时连接；
- 进程杀死、Extension 销毁、系统重启和重复连接；
- 登录取消、凭据吊销、控制面不可达；
- 内存/线程/FD 无持续增长；
- 日志、状态文件和构建产物不泄露密钥；
- 仅支持学习、研究和自部署；应用市场发行与上架不在项目范围内。

## 12. 风险与决策门槛

| 风险 | 当前证据 | 处理方式 |
| --- | --- | --- |
| SIG Go c-shared 在其他商业 HarmonyOS NEXT 设备不兼容 | Mate X7 已通过加载、soak 与 Tailscale engine 门禁 | 设备矩阵逐型号扩展，不从单设备结果外推。 |
| Linux build tag 误选 Tailscale 平台实现 | P0 已通过目标文件选择审计 | 固定补丁、扫描和运行时断言三重防护。 |
| `protectProcessNet()` 在其他设备未覆盖 Go socket | Mate X7 已通过启动顺序、同 PID 与回流门禁 | 新型号重复 P2；失败才回退逐 FD。 |
| TUN 配置变化需要重建 | DNS 与路由变化已在真机触发 generation 串行重建 | 保留 create/destroy 串行化和 generation 门禁。 |
| 官方 OpenHarmony 示例不等于商业手机可用 | 示例面向特定 OpenHarmony 设备/版本 | 在实际目标机保存可复现证据。 |
| 升级 Tailscale 或 Go fork 后不兼容 | 当前固定组合已通过 P0 与真机门禁 | 换版时记录选择依据并重跑 P0–P5。 |

## 13. 证据索引

详细的逐条事实、源码位置、公开项目验证范围和反例见 [implementation-research.md](implementation-research.md)。关键一手资料：

- [HarmonyOS：连接 VPN](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/net-vpnextension)
- [OpenHarmony：VPN Extension 开发指导](https://gitee.com/openharmony/docs/blob/master/zh-cn/application-dev/network/net-vpnExtension.md)
- [OpenHarmony：VPN 官方示例](https://gitee.com/openharmony/applications_app_samples/tree/master/code/BasicFeature/Connectivity/VPN)
- [OpenHarmony-SIG Go](https://gitcode.com/openharmony-sig/ohos_golang_go)
- [OpenHarmony-SIG Go 适配提案](https://gitee.com/open_harmony/dashboard?issue_id=IBFOQM)
- [Go 上游支持平台](https://go.dev/doc/install/source#environment)
- [Tailscale v1.82.5](https://github.com/tailscale/tailscale/releases/tag/v1.82.5)
- [Tailscale Android backend](https://github.com/tailscale/tailscale-android/tree/main/libtailscale)
- [Tailscale C library](https://github.com/tailscale/libtailscale)
- [ClashBox 相邻实现](https://github.com/xiaobaigroup/ClashBox/tree/1fdc47eb9b3bdb715fb04c4b44e1d5238faf83e0)

## 14. 完成定义

只有 P0 可重复构建、P1–P4 在目标 HarmonyOS NEXT 真机通过且证据入库后，README 才能把项目状态从“可行性验证”改为“最小客户端可用”。截至 2026-08-04，这些门禁已经通过；P5 未完成，因此不能扩展为长期稳定、安全可交付或全面兼容的声明。
