# HarmonyOS NEXT 上移植完整 Tailscale 客户端：实施研究

> 调研日期：2026-08-02
>
> 目标：核验 `docs/design.md` 中影响可实施性的关键假设，并给出可验证的工程路径。
>
> 范围：Go runtime / `c-shared`、ArkTS/Node-API、`VpnExtensionAbility`、TUN FD、socket protect、动态路由与 DNS。
>
> 证据优先级：官方源码与构建脚本 > 官方 API 文档与 issue > 有发布物的开源项目 > 项目自述。未找到公开证据的部分明确标为待验证。

## 结论摘要

这个移植方向**具备继续做工程验证的条件**，但还不能据公开资料宣称“完整 Tailscale 客户端已经能在 HarmonyOS NEXT 上运行”。应把当前状态理解为三层证据：

1. **工具链能力已存在。** OpenHarmony-SIG 的 Go 1.24 分支正式提供 `GOOS=openharmony/GOARCH=arm64`、cgo 和 `-buildmode=c-shared`；源码中也包含 OpenHarmony/arm64 的共享库启动代码和 c-shared 测试适配。
2. **相邻端到端架构已有真实项目验证。** ClashBox 的公开源码、签入的 arm64 Go 共享库和持续发布的 HAP 共同证明：在 HarmonyOS NEXT 应用中，可以把 Go 网络核心编译为 `.so`，从 `VpnExtensionAbility` 获取 TUN FD，在 Go 内收发数据包，并把底层 transport socket FD 送回 ArkTS 调用 `protect()`。
3. **Tailscale 专属端到端仍未验证。** 未发现公开的 HarmonyOS NEXT Tailscale 完整客户端，也未发现公开日志证明 OpenHarmony-SIG Go 1.24 已编译并运行当前 Tailscale 的完整依赖闭包。因此 ArkScale 仍必须完成“编译闭包 PoC → 最小 HAP 真机 PoC → Tailscale backend 联调”三道闸门。

实施上应以官方 [`tailscale-android`](https://github.com/tailscale/tailscale-android) 的 `libtailscale` 平台抽象为蓝本，而不是直接采用独立仓库 [`tailscale/libtailscale`](https://github.com/tailscale/libtailscale)。后者包装的是 `tsnet.Server`，适合把单个进程接入 tailnet，并不等价于接管系统流量的完整设备 VPN。

## 证据等级

| 等级 | 含义 | 本文示例 |
| --- | --- | --- |
| A | 可检查源码/构建脚本，且存在公开可安装发布物或持续项目发布 | ClashBox 的 HAP、Go `.so`、TUN/protect 源码 |
| B | 官方源码或官方文档明确实现该能力，但没有找到公开商用真机测试日志 | OpenHarmony-SIG Go 的 c-shared 支持；OpenHarmony VPN API |
| C | 官方 issue、README 或维护者声明，能说明状态但不足以证明端到端运行 | 旧版本 VPN issue、项目 README 描述 |
| D | 基于相邻实现的工程推断，必须由 ArkScale PoC 证实 | 当前 Tailscale 依赖能否零修改编译、进程生命周期是否稳定 |

## 关键事实核验矩阵

| 主题 | 核验结论 | 证据 | 对设计的影响 |
| --- | --- | --- | --- |
| Go 目标系统 | 应使用 OpenHarmony-SIG fork 的 `GOOS=openharmony`，不是把官方 Go 的 `GOOS=linux` 当作默认方案 | B | 替换现有构建说明；固定 fork、分支和提交 |
| `c-shared` | 当前 Go 1.24 fork 明确支持 OpenHarmony/arm64 cgo 与 `c-shared`；旧 fork 的 musl c-shared skip 已被后续提交移除 | B | 可进入真机 PoC，但不能据此宣称生产稳定 |
| HarmonyOS NEXT 兼容 | OpenHarmony 工具链能力与商用 HarmonyOS NEXT 不是同一个证明对象；ClashBox 补上了商用系统上的相邻实现证据 | A+B | 两类证据都要保留；仍需在目标机型/系统版本复验 |
| TUN FD | `VpnConnection.create(config)` 返回 TUN FD；同类项目把 FD 一次性交给 Go 核心，数据包不经过 Node-API | A+B | 桥接层只传控制信息和 FD，禁止逐包跨 Node-API |
| socket protect | API 11 的 `protect(fd)` 只保护指定 socket；API 22 的 `protectProcessNet()` 保护当前进程之后创建的 socket | B | ArkScale 已选择 API 22+，先调用进程级保护再启动 Go；真机失败才回退逐 FD |
| 路由/DNS | Tailscale Android 从 `router.Config` 与 `dns.OSConfig` 动态重建平台 VPN | A | 删除硬编码 `100.64.0.0/10`、客户端 IP 和 MagicDNS 配置 |
| 空路由 | 平台源码在 `routes` 为空时按已启用 IP 家族生成默认路由 | B | 普通 tailnet 模式必须传显式路由，不能用空数组表示“不接管流量” |
| FD 所有权 | 平台 `destroy()` 路径会关闭其保存的原 TUN FD | B | native bridge 先 `dup()`，Go 只持有并关闭副本 |
| VPN 权限 | 第三方 VPN 走 `VpnExtensionAbility` 的用户信任流程；`MANAGE_VPN` 是 system-only 的 VPN 管理权限 | B | 普通应用不要申请 `ohos.permission.MANAGE_VPN` 或设计 ACL 提权流程 |
| `tailscale/libtailscale` | 独立仓库导出 `tsnet` 能力，不提供完整设备 VPN/TUN 平台适配 | A | 不作为核心移植起点 |

## 1. Go runtime 与 `c-shared`

### 1.1 已验证的能力

OpenHarmony-SIG 维护的 [`ohos_golang_go`](https://gitcode.com/openharmony-sig/ohos_golang_go) 当前有 Go 1.24 分支。本文检查的快照为 `release-branch.go1.24` 提交 [`2d8b23f`](https://gitcode.com/openharmony-sig/ohos_golang_go/commit/2d8b23f6923100d8c90d8add9299da2c9d032a20)。其官方[应用编译指南](https://gitcode.com/openharmony-sig/ohos_golang_go/wiki/%E5%BA%94%E7%94%A8%E7%BC%96%E8%AF%91%E6%8C%87%E5%8D%97.md)明确给出：

```bash
export AR="$OHOS_NATIVE/llvm/bin/llvm-ar"
export CC="$OHOS_NATIVE/llvm/bin/aarch64-unknown-linux-ohos-clang"
export CXX="$OHOS_NATIVE/llvm/bin/aarch64-unknown-linux-ohos-clang++"
export GOOS=openharmony
export GOARCH=arm64
export CGO_ENABLED=1

go build -buildmode=c-shared -o libarkscale.so ./cmd/arkscale-mobile
```

源码层还能复核到以下事实：

- [`src/internal/platform/zosarch.go`](https://gitcode.com/openharmony-sig/ohos_golang_go/blob/release-branch.go1.24/src/internal/platform/zosarch.go) 将 `openharmony/arm64` 标为支持 cgo。
- [`src/cmd/go/internal/work/init.go`](https://gitcode.com/openharmony-sig/ohos_golang_go/blob/release-branch.go1.24/src/cmd/go/internal/work/init.go) 允许 OpenHarmony 使用 `c-shared`，并配置 arm64 共享库所需 TLS 模型。
- [`src/runtime/rt0_openharmony_arm64.s`](https://gitcode.com/openharmony-sig/ohos_golang_go/blob/release-branch.go1.24/src/runtime/rt0_openharmony_arm64.s) 包含 `-buildmode=c-shared` 使用的 `_rt0_arm64_openharmony_lib` 启动入口。
- [`src/cmd/cgo/internal/testcshared/cshared_test.go`](https://gitcode.com/openharmony-sig/ohos_golang_go/blob/release-branch.go1.24/src/cmd/cgo/internal/testcshared/cshared_test.go) 已纳入 OpenHarmony c-shared 路径。

这不是从第一天就成立的能力。旧版源码曾因 musl/c-shared 问题跳过 OpenHarmony；后续通过 [issue #34](https://gitcode.com/openharmony-sig/ohos_golang_go/issues/34) 的 arm64 动态 TLS、[issue #35](https://gitcode.com/openharmony-sig/ohos_golang_go/issues/35) 的 c-shared 测试启用，以及 [issue #29](https://gitcode.com/openharmony-sig/ohos_golang_go/issues/29) 的 cgo 外部链接修复逐步解除。2025-12 的 [issue #53 相关改动](https://gitcode.com/openharmony-sig/ohos_golang_go/issues/53)还增加了 cgo 网络接口适配。

### 1.2 必须保留的边界

- 这是 **OpenHarmony-SIG fork**，不是 `go.dev` 发布的上游 Go 官方目标。构建必须固定仓库、分支、提交和校验值，不能只写“Go 1.24+”。
- 官方指南当前明确的是 Linux/x86_64 主机到 OpenHarmony/arm64 的交叉编译。macOS 主机是否可直接使用同一套 fork/预编译工具链，需要在 ArkScale CI 或本地重新验证。
- 该 fork 为降低依赖适配量，在 `GOOS=openharmony` 时让 `runtime.GOOS` 报告 `linux`；OpenHarmony 专用差异要用 `//go:build openharmony` 或 `runtime.IsOpenharmony`。这会提高普通 Linux 代码的复用率，但不保证所有 Linux syscall 在应用沙箱中可用。
- “源码支持 c-shared”不等于“当前 Tailscale 完整依赖闭包可编译”，更不等于“加载、GC、goroutine、DNS、UDP 和进程反复启停已在 HarmonyOS NEXT 真机稳定”。这些都必须由 PoC 给出日志和产物。
- 固定 SIG Go 提交的 `src/net/interface_table_openharmony.go` 在两条接口枚举路径中都创建了 IPv4 UDP ioctl socket，却未调用 `syscall.Close`，同时取得 `getifaddrs` 结果后未释放。真机曾在 30 秒内从 192 增至 724 个 socket，新增项均为未连接 IPv4 UDP；补齐资源释放后，清理版 30 秒回归为 FD `47→46`、RSS `188552→188756 KB`，两次 peer 探针均通过。仓库保留可重放补丁，但该短时结果仍不等于 24 小时稳定。

因此，`docs/design.md` 中 `GOOS=linux` 配合 OHOS clang 的做法不应保留为主路径。它曾被项目自定义工具链采用，但当前可复核的官方 SIG 路径是 `GOOS=openharmony`；也不应照搬第三方历史脚本中的非标准 `-tlsmodegd` 参数。

## 2. 商用 HarmonyOS NEXT 上的真实相邻项目：ClashBox

找到的最有价值项目是 [`xiaobaigroup/ClashBox`](https://github.com/xiaobaigroup/ClashBox)。本文检查的源码快照为提交 [`1fdc47e`](https://github.com/xiaobaigroup/ClashBox/commit/1fdc47eb9b3bdb715fb04c4b44e1d5238faf83e0)。它不仅有 README 声明，还具备源码、签入的 `arm64-v8a/libflclash.so`、持续的 [HAP Releases](https://github.com/xiaobaigroup/ClashBox/releases) 和公开发布记录，因此属于强于“示例或口头声明”的证据。

其实现链条可以逐段检查：

1. [`ClashVpnAbility.ets`](https://github.com/xiaobaigroup/ClashBox/blob/1fdc47eb9b3bdb715fb04c4b44e1d5238faf83e0/entry/src/main/ets/entryability/ClashVpnAbility.ets) 继承 `VpnExtensionAbility`；[`module.json5`](https://github.com/xiaobaigroup/ClashBox/blob/1fdc47eb9b3bdb715fb04c4b44e1d5238faf83e0/entry/src/main/module.json5) 声明 `type: "vpn"`。
2. [`CommonVpnService.ts`](https://github.com/xiaobaigroup/ClashBox/blob/1fdc47eb9b3bdb715fb04c4b44e1d5238faf83e0/proxy_core/src/main/ets/rpc/CommonVpnService.ts) 调用 `createVpnConnection()`、`create(config)` 取得 TUN FD，并封装 `protect(fd)` 与 `destroy()`。
3. [`FlClashVpnService.ts`](https://github.com/xiaobaigroup/ClashBox/blob/1fdc47eb9b3bdb715fb04c4b44e1d5238faf83e0/proxy_core/src/main/ets/rpc/FlClashVpnService.ts) 从 Go 核心获得 IPv4、IPv6、路由与 DNS，动态生成 `VpnConfig`；随后把 TUN FD 传给 Go。它还通过本地 socket 持续接收 transport socket FD，逐个调用 ArkTS `protect(fd)`，成功后再通知 Go 继续。
4. [`tun/tun.go`](https://github.com/xiaobaigroup/ClashBox/blob/1fdc47eb9b3bdb715fb04c4b44e1d5238faf83e0/proxy_core/src/flclash/tun/tun.go) 把传入 FD 设置为 Go 网络核心的 `FileDescriptor`，并关闭自动路由；数据包在 Go 内处理，没有逐包经过 ArkTS/Node-API。
5. [`main_cgo.go`](https://github.com/xiaobaigroup/ClashBox/blob/1fdc47eb9b3bdb715fb04c4b44e1d5238faf83e0/proxy_core/src/flclash/main_cgo.go) 使用第三方 `ohos-napi` 从 Go 直接注册 Node-API 方法和异步回调。
6. [`build.sh`](https://github.com/xiaobaigroup/ClashBox/blob/1fdc47eb9b3bdb715fb04c4b44e1d5238faf83e0/proxy_core/src/flclash/build.sh) 显示其 Go 核心以 `-buildmode=c-shared` 产出 `.so` 并复制进 HAP 库目录。

### 这组证据能证明什么

- HarmonyOS NEXT 上存在真实发布的 “ArkTS VPN Ability + Go c-shared 网络核心” 应用。
- TUN FD 可以一次性交给 Go，Go 可以承担持续的包处理。
- Go 新建 socket 后动态请求 ArkTS `protect(fd)` 是可落地的交互模式。
- IPv4、IPv6、DNS 和路由可以从 Go 核心动态传给 `VpnConfig`。

### 这组证据不能证明什么

- Clash/Mihomo 的依赖闭包不同于 Tailscale；它不能证明 `tailscale.com` 当前源码在 OpenHarmony 上无需修改。
- ClashBox 历史构建脚本使用自定义 Go、`GOOS=linux` 和非标准 TLS 参数。那是该项目的已知工作方式，不应取代 OpenHarmony-SIG 当前官方构建说明。
- 它的 socket protect 通道能作为设计参考，但 ArkScale 仍需验证失败、超时、FD 关闭竞争、并发和网络切换时的行为。
- 公开发布物证明用户侧可运行同类架构，不证明 ArkScale 的 Tailscale 控制面、WireGuard、DERP、MagicDNS、漫游与省电策略端到端成立。

截至本轮对 GitHub、Gitee、OpenHarmony-SIG 与 Tailscale 官方仓库的检索，**ClashBox 是唯一找到的同时公开 Go 源码/c-shared 构建、HarmonyOS NEXT VPN Ability、TUN FD 和逐 socket protect 链路，并提供 HAP Releases 的项目**；没有找到可信的 Tailscale HarmonyOS 客户端仓库。这个结论是检索结果，不是“其他项目一定不存在”的证明。

OpenHarmony 官方 [VPN 示例](https://gitee.com/openharmony/applications_app_samples/tree/master/code/BasicFeature/Connectivity/VPN) 还能提供一组较弱但独立的旁证：其 [`MyVpnExtAbility.ts`](https://gitee.com/openharmony/applications_app_samples/blob/a826ab0e75fe51d028c1c5af58188e908736b53b/code/BasicFeature/Connectivity/VPN/entry/src/main/ets/serviceextability/MyVpnExtAbility.ts#L32) 创建 native UDP socket、调用 `protect`，再把 TUN FD 交给 native；[`vpn_client.cpp`](https://gitee.com/openharmony/applications_app_samples/blob/a826ab0e75fe51d028c1c5af58188e908736b53b/code/BasicFeature/Connectivity/VPN/entry/src/main/cpp/vpn_client.cpp#L74) 在线程中直接读写 TUN 和 socket。README 声称支持 RK3568/OpenHarmony 4.1/API 11，但当前示例还混合了系统 VPN 内容，master manifest 也不是可直接复用的完整第三方 VPN HAP，因此只能证明 native 数据面模式曾被实现，不能替代 HarmonyOS NEXT 商用手机 PoC。

## 3. 选对 Tailscale 移植基线

### 3.1 不要把 `tailscale/libtailscale` 当作完整设备 VPN

独立仓库 [`tailscale/libtailscale`](https://github.com/tailscale/libtailscale) 的 README 和 [`tailscale.go`](https://github.com/tailscale/libtailscale/blob/main/tailscale.go) 表明，它把 `tailscale.com/tsnet` 导出成 c-archive/c-shared API，通过 socketpair 暴露 listen/dial。它解决的是“把某个进程嵌入 tailnet”，没有实现 HarmonyOS 平台的系统 TUN、全局路由、系统 DNS 或 VPN 生命周期。

若目标只是 ArkScale 应用自身访问 tailnet，它可以成为一个更小的备选 PoC；若目标是完整设备 VPN，则不应以它为核心基线。

### 3.2 `tailscale-android/libtailscale` 才是平台移植蓝本

官方 Android 客户端本文检查的快照为提交 [`59f79ba`](https://github.com/tailscale/tailscale-android/commit/59f79ba2837f2091406c56a2ca225249b749ab2e)。关键实现关系如下：

```text
wgengine / ipnlocal
      │
      ├─ router.Config ─┐
      └─ dns.OSConfig ──┴─> VPNFacade.ReconfigureVPN
                                  │
                                  v
                         platform VPN builder
                      地址 / 路由 / DNS / MTU
                                  │
                                  v
                              TUN FD
                                  │
                                  v
                  tun.CreateUnmonitoredTUNFromFD

netns socket creation ──> platform Protect(fd) ──> 物理网络
```

- [`backend.go`](https://github.com/tailscale/tailscale-android/blob/59f79ba2837f2091406c56a2ca225249b749ab2e/libtailscale/backend.go) 创建 userspace engine 和 `ipnlocal.LocalBackend`，把 TUN、Router、DNS 平台适配连接起来。
- [`vpnfacade.go`](https://github.com/tailscale/tailscale-android/blob/59f79ba2837f2091406c56a2ca225249b749ab2e/libtailscale/vpnfacade.go) 同时收集 `router.Config` 与 `dns.OSConfig`，配置变化时触发平台 VPN 重配；其 `SupportsSplitDNS()` 返回 false，是移动端平台适配可参考的边界。
- [`net.go`](https://github.com/tailscale/tailscale-android/blob/59f79ba2837f2091406c56a2ca225249b749ab2e/libtailscale/net.go) 从 `LocalAddrs`、`Routes`、`LocalRoutes`、`Nameservers`、`SearchDomains` 和 MTU 构建新 VPN，取得并接管 TUN FD。
- [`interfaces.go`](https://github.com/tailscale/tailscale-android/blob/59f79ba2837f2091406c56a2ca225249b749ab2e/libtailscale/interfaces.go)、[`IPNService.kt`](https://github.com/tailscale/tailscale-android/blob/59f79ba2837f2091406c56a2ca225249b749ab2e/android/src/main/java/com/tailscale/ipn/IPNService.kt) 和 [`VPNServiceBuilder.kt`](https://github.com/tailscale/tailscale-android/blob/59f79ba2837f2091406c56a2ca225249b749ab2e/android/src/main/java/com/tailscale/ipn/VPNServiceBuilder.kt) 定义并实现 Go 与平台 VPN 的边界。

ArkScale 应尽量复用这一 Go 侧结构，只把 JNI/Kotlin 平台接口替换为 C ABI + Node-API + ArkTS；不要从 `tailscaled` 主程序中重新拼装一套平行架构。

### 3.3 冻结候选版本，不宣称已经兼容

实施设计暂时固定 [Tailscale v1.82.5](https://github.com/tailscale/tailscale/releases/tag/v1.82.5)，commit `e4d64c6faf827a308ec20b39651225178e6743c0`。固定版本的目的，是让 build-tag 审计、平台补丁和真机结果可以复现；这不是该版本已经兼容 OpenHarmony-SIG Go 的证据。P0 必须实际编译完整依赖闭包，若换版本则重新执行 P0–P4，不能跟随 `main` 或 `latest` 构建。

## 4. OpenHarmony/HarmonyOS VPN API 的可实施边界

华为官方的 [HarmonyOS 5.0.0 `vpnExtension` API 参考](https://developer.huawei.com/consumer/cn/doc/harmonyos-references-V5/js-apis-net-vpnextension-V5)，以及 OpenHarmony 官方 [`vpnExtension` API](https://gitee.com/openharmony/docs/blob/dbaf9511609c2997dd5ff66aad6ca418a442d964/zh-cn/application-dev/reference/apis-network-kit/js-apis-net-vpnExtension.md) 与[开发指南](https://gitee.com/openharmony/docs/blob/08986484ea997e1da01ac9221d20dbb0a54b4922/en/application-dev/network/net-vpnExtension.md)确认：

- API 11 起提供第三方 `VpnExtensionAbility`。
- `VpnConnection.create(config)` 返回 TUN 文件描述符。
- `VpnConnection.protect(socketFd)` 让指定 socket 绕过 VPN、直接走物理网络。
- API 22 起的 `VpnConnection.protectProcessNet()` 保护当前进程之后创建的全部 socket，先前创建的 socket 不受影响。
- `VpnConfig` 包含地址、路由、DNS、搜索域、MTU、IPv4/IPv6 开关和应用白/黑名单。
- 路由的接口名固定为 `vpn-tun`，目前最多配置 1024 条路由。
- 系统目前只支持一个活动 VPN；未受信任应用启动时由系统显示用户授权对话框。

OpenHarmony 的 SDK 类型声明进一步显示，现有设计示例的 `VpnConfig` 结构不完整：`addresses` 元素必须是包含 `NetAddress` 与 `prefixLength` 的 `LinkAddress`；每个 `RouteInfo` 还必须包含 `interface`、`destination`、`gateway`、`hasGateway`、`isDefaultRoute`。可直接复核 [`@ohos.net.vpnExtension.d.ts`](https://gitee.com/openharmony/interface_sdk-js/blob/c349adc73e2ec1f61f6fca489b5af059e3ed6999/api/@ohos.net.vpnExtension.d.ts#L161) 和 [`@ohos.net.connection.d.ts`](https://gitee.com/openharmony/interface_sdk-js/blob/c349adc73e2ec1f61f6fca489b5af059e3ed6999/api/@ohos.net.connection.d.ts#L2029)。API 22+ 目标的结构应至少满足：

```ts
const config: vpnExtension.VpnConfig = {
  addresses: [{
    address: { address: tunAddress, family },
    prefixLength: tunPrefixLength
  }],
  routes: routesFromBackend.map(route => ({
    interface: 'vpn-tun',
    destination: {
      address: { address: route.address, family: route.family },
      prefixLength: route.prefixLength
    },
    gateway: {
      address: route.family === 1 ? '0.0.0.0' : '',
      family: route.family
    },
    hasGateway: false,
    isDefaultRoute: route.prefixLength === 0
  })),
  dnsAddresses: dnsFromBackend,
  mtu,
  isIPv4Accepted: enableIPv4,
  isIPv6Accepted: enableIPv6,
  isBlocking: false
};
```

Mate X7 真机进一步确认：`hasGateway=false` 时若仍给 IPv6 `gateway.address` 传 `::`，系统会把它作为 next-hop 并使 Tailscale ULA 连接返回 `ENETUNREACH`；空字符串才与“无网关”语义一致。`NetAddress.family` 省略时默认 IPv4，IPv6 socket 也必须显式传 `2`。

平台源码的[网络链路配置实现](https://gitee.com/openharmony/communication_netmanager_ext/blob/0f8c2ef2f0e1fb1a409f3613096948e21da3e26b/services/vpnmanager/src/net_vpn_impl.cpp#L292)还有一个容易踩坑的行为：当 `routes` 省略或为空时，系统会根据 `isIPv4Accepted` / `isIPv6Accepted` 自动生成默认路由。也就是说，空数组实际可能形成全隧道；普通 tailnet 模式必须传入从 backend 计算出的显式路由。

官方还提供了 [`applications_app_samples/VPN`](https://gitee.com/openharmony/applications_app_samples/tree/master/code/BasicFeature/Connectivity/VPN) 示例。不过版本必须作为测试矩阵的一部分：[公开 issue ICE4CK](https://gitee.com/openharmony/communication_netmanager_ext/issues/ICE4CK) 记录了同一官方示例在 OpenHarmony 4.1 失败、在 5.0 成功的情况。ArkScale 应只对“明确记录过的 HarmonyOS NEXT 版本 + 目标机型”给出兼容性结论。

### 权限纠正

`ohos.permission.MANAGE_VPN` 不应作为普通第三方 VPN 的必需权限。OpenHarmony 的[权限定义源文件](https://github.com/openharmony/security_access_token/blob/master/services/accesstokenmanager/permission_definitions.json)将其定义为 `system_grant`、`system_basic`、`availableType: SYSTEM`；这是系统 VPN 管理权限。平台[启动与授权实现](https://gitee.com/openharmony/communication_netmanager_ext/blob/0f8c2ef2f0e1fb1a409f3613096948e21da3e26b/frameworks/js/napi/vpnext/src/vpn_module_ext.cpp#L181)会为自身 bundle 的第三方 VPN 显示用户授权对话框，[系统服务权限分支](https://gitee.com/openharmony/communication_netmanager_ext/blob/0f8c2ef2f0e1fb1a409f3613096948e21da3e26b/frameworks/js/napi/vpn/src/networkvpn_service.cpp#L643)也会在没有 `MANAGE_VPN` 时检查该用户授权。第三方应用应只声明实际需要的普通权限，例如联网所需的 `ohos.permission.INTERNET`。是否还需其他权限必须以目标 SDK 编译错误和官方 API 标注为准，不要预设 ACL/特权签名。

## 5. 可实施的平台接口

建议先把 ArkTS ↔ Go 的边界冻结为最小控制面。数据包始终由 Go 直接读写 TUN FD。

```text
Start(config/stateDir) -> async result
Stop() -> async result
SetWantRunning(bool)
SetAuthKeyOnce(secret) / StartLogin()
NotifyNetworkChanged(networkSnapshot)

Go -> ArkTS: ReconfigureVPN(VPNConfig) -> { tunFd | error }
Go -> ArkTS: ProtectSocket(fd) -> { ok | error }
Go -> ArkTS: StatusChanged(status)
Go -> ArkTS: LoginURL(url)
Go -> ArkTS: Log(record)
```

### 5.1 TUN FD 与生命周期

- `ReconfigureVPN` 的输入必须来自 Tailscale 的 `router.Config` 与 `dns.OSConfig`，至少携带 `LocalAddrs`、`Routes`、`LocalRoutes`、`Nameservers`、`SearchDomains` 和 MTU。
- ArkTS 串行化 `create/destroy/recreate`，避免两个重配同时操作唯一 VPN。
- 首版可以仿照 Tailscale Android，在有效配置变化时重建 VPN/TUN；应明确记录短暂断网窗口。官方 API 没有在本文证据中提供原地更新已建 TUN 的方法。
- FD 所有权必须写进接口契约。平台的 [`vpn_interface.cpp`](https://gitee.com/openharmony/communication_netmanager_ext/blob/0f8c2ef2f0e1fb1a409f3613096948e21da3e26b/frameworks/native/netvpnclient/src/vpn_interface.cpp#L103) 显示 `destroy()` 路径会关闭平台保存的 TUN FD，因此 native bridge 应先 `dup(tunFd)`，只把副本交给 Go。Go 只关闭副本，`VpnConnection.destroy()` 管理原 FD，避免 double-close 和 FD 复用风险。
- Stop 顺序应固定为：停止接收新配置 → 停 Go 数据面并等待退出 → Go 关闭副本 FD → `VpnConnection.destroy()` 关闭平台原 FD → 清理回调。异常路径也要幂等。

### 5.2 socket protect

Tailscale Android 在 [`backend.go`](https://github.com/tailscale/tailscale-android/blob/59f79ba2837f2091406c56a2ca225249b749ab2e/libtailscale/backend.go) 通过 `netns.SetAndroidProtectFunc` 为 socket 安装平台 protect 回调。ArkScale 的 API 22+ 产品决策允许使用更小的进程级方案：

- 创建 `VpnConnection` 后，先 `await protectProcessNet()`，成功后才能启动 Go backend。
- Extension、Node-API 和 Go `.so` 必须同进程；P2 记录 PID 并用 socket 回流测试验证契约。
- OpenHarmony netns 平台实现不再做逐 FD 回调，只需避免进入 Linux `SO_MARK` / `SO_BINDTODEVICE` 路径。
- 网络切换后仍触发 Tailscale 重绑；新建 socket 应继续自动受进程级保护。
- 若 P2 证明进程保护没有覆盖 Go/cgo socket，再采用 Android/ClashBox 已验证的逐 FD 请求确认模式。

### 5.3 动态路由与 DNS

现有设计中的固定地址、`100.64.0.0/10` 和 `100.100.100.100` 只能作为 UI 示例，不能进入实际 `VpnConfig`。真实值必须由 engine 配置驱动：

- 地址：`router.Config.LocalAddrs`
- 允许路由：`router.Config.Routes`
- 本地排除路由：`router.Config.LocalRoutes`
- DNS：`dns.OSConfig.Nameservers`
- 搜索域：`dns.OSConfig.SearchDomains`

如果目标 SDK 的 `RouteInfo.isExcludedRoute` 在实测中可用，优先直接表达 `LocalRoutes`；如果不可用，可复用 Tailscale Android [`ranges_calc`](https://github.com/tailscale/tailscale-android/tree/59f79ba2837f2091406c56a2ca225249b749ab2e/libtailscale/ranges_calc) 的“允许路由减本地排除路由”逻辑。Android 实现自己把计算结果限制在 500 条，而 OpenHarmony 文档的系统上限是 1024 条；ArkScale 应在提交给系统前再次检查数量，超限时明确报错，不能静默截断。

OpenHarmony API 22 起提供进程级 `protectProcessNet()`。ArkScale 已将 compatible SDK 提升到 API 22 并选用该接口；仍没有 HarmonyOS 商业版目标设备上的 ArkScale 真机证据，因此 P2 是硬门禁。

平台只接收 DNS 服务器和搜索域，不表达 Tailscale 的整套分域解析策略。可先遵循 Android `VPNFacade.SupportsSplitDNS() == false` 的平台能力模型，让 Tailscale DNS manager 决定送给平台的最终 `dns.OSConfig`，不要在 ArkTS 自行硬编码 MagicDNS。

## 6. Node-API / C ABI 建议

OpenHarmony-SIG 的[原生 Node-API 指南](https://gitee.com/openharmony-sig/tpc_c_cplusplus/blob/master/docs/hello_napi.md)说明 ArkTS/JS 与 C/C++ 的标准桥接方式。ClashBox 证明 Go 也能借助第三方库直接注册 Node-API，但 ArkScale 没有必要在第一版引入这层额外耦合。

建议结构为：

```text
ArkTS
  │ Node-API（参数校验、Promise、线程安全回调）
  v
薄 C++ bridge
  │ 稳定 C ABI（只传标量、UTF-8/长度、opaque handle）
  v
Go c-shared
```

约束：

- Go 导出函数立即返回或由 worker goroutine 执行，不能长期阻塞 ArkTS/UI 线程。
- Go 后台线程不得直接调用普通 `napi_env`；异步事件经线程安全回调回到 ArkTS。
- 跨边界对象使用句柄和复制后的字节串，不保留指向 ArkTS/JS 内存的 Go 指针。
- 所有导出调用返回结构化错误码；`Start/Stop/ReconfigureVPN/ProtectSocket` 都必须可超时、可取消、可重复调用。
- 日志、状态和配置可以跨 Node-API；TUN 数据包不跨 Node-API。

## 7. 分阶段实施闸门

只有上一阶段留下可复核产物，才进入下一阶段。

### P0：Tailscale 依赖闭包编译

目标：回答“当前 Tailscale 在固定 Go fork 上到底需要改多少”。

- 固定 Tailscale commit 与 OpenHarmony-SIG Go commit。
- 只编译最小 backend 包和 C ABI，不做 UI。
- 记录所有 build tag、syscall、`x/sys/unix`、netlink、DNS、文件权限和动态链接错误。
- 验收：生成 arm64 `libarkscale.so` 与头文件；保存完整、可重复的构建命令；禁止未说明的源码复制和全局替换。

### P1：最小 Go c-shared HAP 真机

目标：隔离 Go runtime/c-shared 风险。

- HAP 加载 `.so`，调用同步函数和异步 goroutine 回调。
- 测试 GC、并发、定时器、文件读写、UDP/TCP、TLS、系统 DNS、反复 Start/Stop，以及 VPN extension 进程被系统销毁后的恢复。
- 验收：至少在一台目标 HarmonyOS NEXT 真机连续运行 30 分钟、执行 100 次加载/启停循环，无崩溃、死锁和持续内存增长；保留系统版本、机型、日志和 HAP 校验值。

### P2：最小 VPN/TUN/protect PoC

目标：验证平台数据面，不接 Tailscale 控制面。

- `VpnExtensionAbility` 建 TUN；Go 从 FD 读取并回写可识别测试包。
- 在 `protectProcessNet()` 成功后由 Go 创建至少 100 个 UDP/TCP socket，验证全部绕过 TUN；同时测试保护调用失败时 Go 不启动。
- Wi-Fi/移动网络切换、锁屏、前后台、VPN 重建。
- 验收：抓包或双端日志证明 TUN 数据经过 Go；受保护 socket 不回流 TUN；未保护 socket 的失败场景可被监测。

### P3：接入 Tailscale backend

目标：把 Android 平台契约移植到 HarmonyOS。

- 使用 `wgengine.NewUserspaceEngine` + `ipnlocal.NewLocalBackend`。
- 由 `router.Config`/`dns.OSConfig` 触发动态 VPN 重配。
- 接入状态存储、登录 URL/auth key、日志和网络变化通知。
- 验收：登录自建或官方控制面；访问至少一个 peer；MagicDNS、IPv4/IPv6、DERP 回退各有明确测试结果。

### P4：端到端网络

- 交互式登录后访问至少一个 peer；
- 分别验证 DERP 回退和可观测的直连；
- 验证 MagicDNS、Tailscale IPv4/IPv6；
- 验证 Wi-Fi/蜂窝切换、断网恢复和 socket 重新 protect；
- 验证至少一次控制面路由/DNS 变化后的 TUN 重建。

截至 2026-08-04，目标真机已通过 MagicDNS 关闭/恢复以及临时子网路由批准/撤销两组控制面变化；每次都创建并接管新 TUN，恢复原配置后的 peer、TCP 与 MagicDNS 探针继续通过。

出口节点、发布子网路由、Taildrop 和应用分流不属于首版门禁，待基础端到端稳定后再单独设计。

### P5：稳定性、安全与可交付性

- 24 小时长稳、反复漫游、休眠唤醒、低内存回收、异常终止恢复。
- 登录取消、凭据吊销、认证失败和控制面不可达都有可恢复结果。
- 内存、线程和 FD 无持续增长；Stop 后无残留 VPN 与后台连接。
- 明确支持的 HarmonyOS NEXT 版本和设备矩阵。
- 生成 SBOM、第三方许可证、固定工具链下载与校验方式。

## 8. 当前未知项与停止条件

以下均未被公开一手资料证明，不能写成既成事实：

- 当前 Tailscale commit 能在 OpenHarmony-SIG Go 1.24 上无补丁编译。
- API 22 进程级保护能覆盖 Go/cgo 创建的全部 Tailscale socket。
- HarmonyOS NEXT 的目标版本对排除路由、IPv6、DNS 搜索域和后台 VPN 生命周期与 OpenHarmony 文档完全一致。
- Go c-shared 在 VPN extension 的独立进程中长时间运行、重复装载和系统回收后稳定。
- AppGallery 上架政策、商用签名和不同地区固件行为与自签 HAP 相同。

遇到下列任一情况应暂停完整 UI 开发，优先解决平台 PoC：

- P0 需要维护大面积 Tailscale fork，而不是少量平台 build tag/接口适配。
- P1 出现不可控 runtime 崩溃、线程/TLS 初始化失败或重复启停泄漏。
- P2 无法证明 `protectProcessNet()` 覆盖同进程 Go/cgo socket。
- 路由/DNS 无法随 backend 配置变化原子或可恢复地重建。

## 对现有 `design.md` 的直接修订清单

1. 把 `GOOS=linux` 主路径改为固定 OpenHarmony-SIG Go 1.24 commit 的 `GOOS=openharmony`；删除“POSIX 兼容即可标准静态链接”的推断。
2. 不把 `tailscale/libtailscale` 描述为完整设备 VPN 基线；改用 `tailscale-android/libtailscale` 的 backend/VPNFacade 架构。
3. 删除 `ohos.permission.MANAGE_VPN` 与 ACL/特权签名作为第三方 VPN 必需步骤的描述。
4. 修正 `VpnConfig` 类型；明确空路由会产生默认路由，普通 tailnet 模式传显式路由。
5. 删除运行配置中的固定 Tailscale IP、`100.64.0.0/10` 与 MagicDNS；改为 `router.Config`/`dns.OSConfig` 驱动。
6. API 22+ 先用 `protectProcessNet()` 后启动 Go；只有 P2 失败时才引入逐 socket 协议。
7. 明确 TUN FD 只跨桥一次，数据包留在 Go 内；native `dup()` 后交给 Go，并补充重配串行化和 Stop 顺序。
8. 在正式功能开发前增加 P0/P1/P2 三个硬性 PoC 闸门，并把“支持 HarmonyOS NEXT”限定到已记录的系统版本与机型。
