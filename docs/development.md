# ArkScale 开发者指南

本文面向需要构建、移植、调试或验证 ArkScale 的开发者。普通使用说明见项目 [README](../README.md)。

## 开发状态与证据边界

ArkScale 已完成 P0–P4：固定依赖构建、Go `c-shared` 真机运行、HarmonyOS VPN/TUN、Tailscale backend 接入和端到端网络均已通过目标真机门禁。当前处于 P5，仍需完成 24 小时长稳、低内存恢复和剩余控制面异常验证。

当前证据不能外推为所有 HarmonyOS NEXT 设备均受支持。逐设备结果和未覆盖项见[设备验证矩阵](device-matrix.md)，技术事实与公开证据见[实现研究](implementation-research.md)。

## 固定基线

| 组件 | 固定版本 |
| --- | --- |
| compatible SDK | API 22 |
| compile SDK | API 24 |
| 目标 ABI | `arm64-v8a` / `aarch64-linux-ohos` |
| OpenHarmony-SIG Go | `release-branch.go1.24`，commit `2d8b23f6923100d8c90d8add9299da2c9d032a20`（Go 1.24.5） |
| Tailscale | v1.82.5，commit `e4d64c6faf827a308ec20b39651225178e6743c0` |
| P0 主机 | Linux x86_64 |
| HAP 工具 | DevEco Studio 6.1.1、同一 fnm 环境中的 Node 与 pnpm |

Tailscale 和 Go 版本是已通过当前门禁的冻结组合。升级任一依赖时，必须重新执行依赖闭包构建、平台路径审计和真机验收。

## 关键实现约束

- 使用 OpenHarmony-SIG Go 的 `GOOS=openharmony` 工具链，不能用上游 Go 的 `GOOS=linux` 代替；
- 以 `tailscale-android/libtailscale` 为全设备 VPN 移植蓝本；`tailscale/libtailscale` 主要提供 `tsnet` socket API；
- 三方 VPN 不申请系统级 `ohos.permission.MANAGE_VPN`；
- 地址、路由、DNS 和 MTU 由 Tailscale backend 动态提供，不硬编码 CGNAT 或 MagicDNS 地址；
- API 22+ 在启动 Go 前调用 `VpnConnection.protectProcessNet()`；
- ArkUI、VPN Extension、Node-API 和 Go engine 的控制数据跨 ABI 传递，数据包由 Go 通过复制后的 TUN FD 直接收发。

更完整的架构、C ABI、生命周期和平台适配说明见[实施设计](design.md)。

## 架构概览

```text
EntryAbility / ArkUI
        │ 用户操作、状态
        ▼
VpnExtensionAbility ─── VpnConnection create/protect/destroy
        │ 配置、事件、TUN FD
        ▼
Node-API C++ addon ──── FD 所有权、异步事件、线程切换
        │ 稳定 C ABI
        ▼
libarkscale_engine.so ─ Tailscale LocalBackend / wgengine / netstack
```

Extension、Node-API addon 和 Go 动态库必须在同一 VPN 进程中。Node-API 只处理生命周期、配置、事件和 FD，不转发逐个数据包。

## 构建 HAP

安装工程依赖并构建：

```bash
ohpm install
pnpm run build:hap
pnpm run verify:hap
```

如需单独校验指定 HAP，必须传入文件路径：

```bash
pnpm run validate:hap -- /path/to/arkscale.hap
```

未签名产物位于：

```text
entry/build/default/outputs/default/entry-default-unsigned.hap
```

在 DevEco Studio 的 Signing Configs 中配置本地签名后，还会生成 `entry-default-signed.hap`。`verify:hap` 会检查 unsigned 和本地存在的 signed HAP，确认目标 ABI、API、权限以及内嵌原生库均为当前产物。

首次真机运行时，在 DevEco Studio 中选择已连接设备并运行 `entry`。不要提交签名文件、密码或设备凭据。

## 构建固定 Go/Tailscale 依赖

P0 必须在 linux/amd64 容器中运行，并挂载已解压的 Linux OpenHarmony SDK API 24：

```bash
ARKSCALE_LINUX_SDK=/absolute/path/to/linux-sdk \
  pnpm run build:p0
```

脚本会执行以下门禁：

- 校验 SDK 元数据和 Clang 架构；
- 获取并校验固定的 Go 与 Tailscale commit；
- 只允许仓库登记补丁产生的精确源码差异；
- 构建固定 SIG Go 工具链和 `c-shared` engine；
- 检查 ELF 架构、动态依赖和 C ABI 导出符号；
- 在 `build/compliance/` 生成 SPDX SBOM 和第三方许可证包。

默认模块代理为 `https://goproxy.cn,direct`，可以通过标准 `GOPROXY` 环境变量覆盖，checksum 校验始终启用。

固定 SIG Go 提交中的 OpenHarmony `net.Interfaces()` 曾遗漏关闭 ioctl socket 和释放 `getifaddrs` 结果。修复保存在 `patches/ohos-go/`，由构建脚本幂等重放；升级 SIG Go 时必须重新审计。

## P1 smoke 构建

使用与 P0 相同的 Linux SDK：

```bash
ARKSCALE_LINUX_SDK=/absolute/path/to/linux-sdk \
  pnpm run build:p1
```

P1 会先执行完整 P0 固定输入门禁，再生成不含 Tailscale 的 Go smoke library，最后构建并校验 HAP。真机页面显示 `Go smoke: PASS` 才代表首次加载通过。

30 分钟 smoke 测试要求 ArkScale 保持前台并保持屏幕常亮，建议连接电源。最终 PASS 还要求 Go worker 产生至少 17000 个 100 ms tick，避免只依赖 ArkTS 墙上时间。

## 真机网络验收

首次连接需完成系统 VPN 授权和 Tailscale 交互登录。基础通过条件包括：

- 状态进入 `Backend: RUNNING`；
- Extension 显示 `READY configGen=...`；
- Native 显示 `protected/tunDup/engineTun/sameProcess=PASS`；
- 停止后 backend 为 `STOPPED`，FD 所有权门禁仍为 PASS。

端到端门禁包括：

1. 从 NetMap 读取 peer，并通过 TSMP 探针；
2. MagicDNS 经 VPN DNS 解析到目标 peer 的 Tailscale IP；
3. Harmony 原生 `TCPSocket` 分别访问 peer IPv4 和 Tailscale ULA IPv6；
4. 观察 DERP 与公网 UDP `direct` 路径；
5. 切换 Wi-Fi、蜂窝、飞行模式并验证恢复；
6. 改变控制面 DNS 或路由，确认 TUN 串行重建后网络仍可用；
7. 执行强制停止、设备重启和多轮完整启停。

HarmonyOS `NetAddress.family` 省略时默认为 IPv4，因此 IPv6 socket 必须显式使用 family `2`。对于 `hasGateway=false` 的 IPv6 VPN 路由，`gateway.address` 应留空，不能传入 `::`。

## 分阶段门禁

| 阶段 | 目标 |
| --- | --- |
| P0 | 固定 Go/Tailscale 依赖，编译 engine 并登记平台补丁 |
| P1 | 验证 Go runtime、`c-shared` 加载、100 次启停和 30 分钟 smoke |
| P2 | 验证 VPN 授权、TUN、process protect、FD 所有权和重建 |
| P3 | 接入 LocalBackend，验证登录、持久化和动态 VPN 配置 |
| P4 | 验证 peer、DERP/直连、MagicDNS、IPv4/IPv6 和网络切换 |
| P5 | 验证 24 小时长稳、异常恢复、安全和自部署交付性 |

详细验收标准见[实施设计](design.md)。任何前置门禁失败时，不应继续扩大功能范围。

## 安全与合规检查

提交前执行：

```bash
pnpm run check:secrets
```

不要提交 auth key、OAuth secret、节点私钥、可复用登录 URL、签名材料或 Signing Config 密码。发布候选应从对应 commit 重新运行 P0，并将 `build/compliance/` 与 HAP 一起归档。完整要求见[合规与安全交付](compliance.md)。

## 仓库结构

```text
.
├── AppScope/              # 应用级资源与 bundle 配置
├── docker/                # linux/amd64 P0 builder
├── docs/                  # 用户之外的设计、研究与验证文档
├── engine/                # Go c-shared C ABI 与依赖闭包入口
├── entry/                 # Stage/ArkTS/Node-API 模块
├── patches/ohos-go/       # OpenHarmony-SIG Go 可重放修复
├── patches/tailscale/     # Tailscale 平台补丁登记
├── smoke/                 # 不含 Tailscale 的 Go runtime 探针
└── scripts/               # HAP、依赖、工具链和 engine 构建
```
