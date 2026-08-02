# ArkScale

ArkScale 是一个实验性项目，目标是在 HarmonyOS NEXT 上实现可自用的 Tailscale 全设备 VPN 客户端。

> 当前仓库已完成 P0 和 P1：固定 Tailscale 依赖闭包已生成并校验 AArch64 engine，最小 Go `c-shared` HAP 已通过真机加载、100 次启停和 30 分钟持续运行；这还不是可用的 Tailscale 客户端。

## 当前判断

这条路线值得做 PoC，但还不能宣称“已支持 HarmonyOS NEXT”。截至 2026-08-02，证据边界如下：

| 层级 | 已确认 | 尚未确认 |
| --- | --- | --- |
| HarmonyOS VPN | API 11 起提供三方 `VpnExtensionAbility`、TUN FD 和 `create/destroy`；API 22 起提供进程级 `protectProcessNet()`。普通三方 VPN 基线是 `INTERNET` 权限加系统用户授权。 | 目标商业机型上的全部路由、DNS、重建与后台生命周期行为。 |
| Go | OpenHarmony-SIG Go 1.24 分支支持 `GOOS=openharmony/arm64`、cgo 和 `c-shared`。 | 该 fork 与 Tailscale 完整依赖在目标 HarmonyOS NEXT 手机上的稳定性。 |
| 相邻项目 | ClashBox 公开实现了 HarmonyOS NEXT 上的 Go `.so`、VPN Ability、TUN FD 与逐 socket `protect`，并提供 HAP Release。 | ClashBox 不是 Tailscale，不能证明 WireGuard、DERP、MagicDNS 和 Tailscale 控制面可用。 |
| Tailscale | Android 官方客户端提供了可参考的移动端 backend、可替换 TUN、路由/DNS 回调和 socket protect 架构。 | 没有找到可信的 HarmonyOS NEXT 完整 Tailscale 客户端或端到端日志。 |

## 已纠正的关键假设

- 使用固定的 [OpenHarmony-SIG Go](https://gitcode.com/openharmony-sig/ohos_golang_go) `GOOS=openharmony` 工具链；不把上游 Go 的 `GOOS=linux` 当成兼容方案。
- 以 [`tailscale-android/libtailscale`](https://github.com/tailscale/tailscale-android/tree/main/libtailscale) 为全设备 VPN 的移植蓝本。独立的 [`tailscale/libtailscale`](https://github.com/tailscale/libtailscale) 主要导出 `tsnet` socket API，不接管系统 TUN。
- 不申请 `ohos.permission.MANAGE_VPN` 作为三方 VPN 基线；该权限属于系统 VPN 管理能力。
- 地址、路由、DNS 和 MTU 全部由 Tailscale backend 动态提供；不硬编码 CGNAT 网段或 MagicDNS 地址。
- 首版要求 API 22+：在启动 Go 前调用 `VpnConnection.protectProcessNet()`，让同进程之后创建的外层 socket 自动绕过 VPN；P2 必须验证 Extension、Node-API 和 Go 同进程及真机保护效果。
- Node-API 只处理生命周期、配置、事件和 FD；Go 通过 `dup()` 后的 TUN FD 直接收发数据包。

## 固定候选基线

- compatible SDK API 22、compile SDK API 24，arm64 真机；
- OpenHarmony-SIG Go `release-branch.go1.24`，commit `2d8b23f6923100d8c90d8add9299da2c9d032a20`（仓库版本 `go1.24.5`）；
- Tailscale v1.82.5，commit `e4d64c6faf827a308ec20b39651225178e6743c0`；
- Linux x86_64 交叉编译主机，目标 `openharmony/arm64`。

Tailscale 版本只是冻结的移植候选，必须通过依赖闭包编译和真机测试才能升级为“受支持基线”。

## 本地构建

HAP 构建要求 DevEco Studio 6.1.1，以及同一个当前 fnm 环境中的 Node 和 pnpm。脚本使用 DevEco 自带的 SDK、JBR 和 Hvigor，不会下载 wrapper 固定的 pnpm：

```bash
ohpm install
pnpm run build:hap
pnpm run verify:hap
```

输出位于 `entry/build/default/outputs/default/entry-default-unsigned.hap`。当前没有签名配置，因此只生成未签名 HAP。

P0 必须在 linux/amd64 容器中运行，并挂载已解压的 Linux OHOS SDK；目录下应存在 `native/llvm/bin/clang`：

```bash
ARKSCALE_LINUX_SDK=/absolute/path/to/linux-sdk \
  pnpm run build:p0
```

P0 默认使用 `https://goproxy.cn,direct` 下载公开 Go modules；可通过标准 `GOPROXY` 环境变量覆盖，checksum 校验保持启用。

该命令会获取并校验固定的 Go/Tailscale commit，构建 SIG Go 工具链、编译 `c-shared` engine，并检查架构、动态依赖和 C ABI 导出符号。当前固定输入已经通过 P0。

当前 `engine/cmd/arkscale` 只用于强制编译 `ipnlocal` 依赖闭包；除参数校验外，ABI 返回 `ARKSCALE_ERROR_NOT_IMPLEMENTED`。它不是可连接的 Tailscale backend。

P0 通过后，使用同一个 Linux SDK 和本地 builder 镜像构建 P1。该命令先生成不含 Tailscale 的 Go smoke library，再构建并校验 HAP：

```bash
ARKSCALE_LINUX_SDK="$HOME/harmony-linux/command-line-tools/sdk/default/openharmony" \
  pnpm run build:p1
```

P1 页面会调用 Go runtime 的 goroutine、channel、timer 和 GC 冒烟测试。真机上的首次加载、100 次启停和 30 分钟稳定性验证均已通过。

首次真机验证需在 DevEco Studio 的 Signing Configs 中配置调试签名，选择已连接设备并运行 `entry`。页面显示 `Go smoke: PASS` 才算通过首次加载；签名文件和凭据不得提交到仓库。

30 分钟测试期间应用会请求主窗口保持亮屏。请保持 ArkScale 在前台，并建议连接电源；手动锁屏、切到后台或系统拒绝保持亮屏时，本次结果无效。最终 PASS 除了要求经过 30 分钟，还要求 Go worker 实际产生至少 17000 个 100 ms tick，避免仅凭 ArkTS 墙上时间误判。

P2 页面提供 `Start VPN probe` / `Stop VPN probe`。首次启动应出现系统 VPN 授权；允许后预期依次显示 `Control: START REQUESTED`、`Extension: READY ... process=SEPARATE` 和 `Native in VPN process: READY protected=PASS tunDup=PASS`，停止后 Native 预期显示 `STOPPED dupOwnership=PASS`。HarmonyOS 会把 VPN Extension 放在应用的 `:vpn` 进程中，因此 Go engine 必须从 Extension 启动。当前探针只路由保留测试地址 `192.0.2.2/32`；尚未实现 packet echo 或接入 Tailscale。

## 实施门禁

1. 固定 Tailscale 和 Go commit，完成依赖闭包编译并登记所有平台补丁。
2. 用不含 Tailscale 的最小 Go `c-shared` HAP 验证加载、goroutine、GC、文件、UDP、DNS、TLS 和 100 次启停。
3. 完成 TUN/echo/process-protect PoC，验证同进程、FD 所有权、VPN 重建和网络切换。
4. 接入 Tailscale mobile backend，由 `router.Config` / `dns.OSConfig` 动态创建 TUN。
5. 在目标真机验收登录、peer TCP、DERP/直连、MagicDNS、IPv4/IPv6、漫游和异常恢复。

任何前置门禁未通过，都不进入 UI 完善或功能扩展。

## 文档

- [实施设计](docs/design.md)：版本锁定、架构、C ABI、构建命令、生命周期、平台补丁和 P0–P5 验收标准。
- [事实核对与开源项目验证](docs/implementation-research.md)：逐项证据、源码链接、ClashBox 与 Tailscale Android 的可借鉴范围，以及仍待 ArkScale 验证的事项。

## 仓库状态

```text
.
├── AppScope/              # 应用级资源与 bundle 配置
├── docker/                # linux/amd64 P0 builder
├── docs/                  # 设计与事实核对
├── engine/                # Go c-shared C ABI 与依赖闭包入口
├── entry/                 # Stage/ArkTS/Node-API 模块
├── patches/tailscale/     # 可重放的平台补丁登记
├── smoke/                 # 不含 Tailscale 的 P1 Go runtime 探针
└── scripts/               # HAP、依赖、工具链和 engine 构建
```

当前只推进“依赖闭包编译 + 最小 Go HAP + TUN/protect PoC”，不先开发完整 UI。

## 安全

不把 auth key、OAuth secret、节点私钥、可复用登录 URL 或签名材料写入源码、日志和仓库。移动客户端优先使用交互式登录；自动注册仅用于测试，并使用一次性、最小权限、可撤销的凭据。Tailscale 状态保存在应用私有目录。

## 主要资料

- [HarmonyOS：连接 VPN](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/net-vpnextension)
- [OpenHarmony：VPN Extension 指南](https://gitee.com/openharmony/docs/blob/master/zh-cn/application-dev/network/net-vpnExtension.md)
- [OpenHarmony 官方 VPN 示例](https://gitee.com/openharmony/applications_app_samples/tree/master/code/BasicFeature/Connectivity/VPN)
- [OpenHarmony-SIG Go 适配提案](https://gitee.com/open_harmony/dashboard?issue_id=IBFOQM)
- [Tailscale v1.82.5](https://github.com/tailscale/tailscale/releases/tag/v1.82.5)
- [ClashBox](https://github.com/xiaobaigroup/ClashBox)
