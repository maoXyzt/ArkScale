# 发现与决策

## 需求
- 实现 HarmonyOS NEXT 上的 Tailscale 全设备 VPN。
- 首版 API 22+、arm64、官方 Tailscale 控制面。
- 使用 `protectProcessNet()`，不实现逐 socket protect 回调。

## 研究发现
- 初始仓库只有 README 和设计/研究文档，没有工程源码；当前已补齐最小 HAP 与 P0 构建骨架。
- 本机是 macOS arm64，安装了 DevEco Studio；随附 OpenHarmony SDK 为 API 24、版本 6.1.1.125。
- 本机 SDK 含 OHOS Clang 15.0.4、HDC 和 Hvigor，但当前没有连接设备。
- 本机有 Rancher Desktop Docker CLI，daemon 是否可用仍需验证。
- Mac SDK 内的 Clang 是 Darwin 可执行文件，不能直接在 Linux 容器运行；P0 需要 Linux 主机版 OHOS Native SDK。
- OpenHarmony-SIG Go 固定 commit 支持 `GOOS=openharmony/arm64` 与 c-shared，但 Tailscale 闭包尚未实编。
- Tailscale 会因 SIG Go 的 Linux build tag 兼容行为选入部分 Linux 专用代码，P0 必须隔离 netns/netmon/router 系统实现。
- API 22 `protectProcessNet()` 只保护调用后创建的当前进程 socket，因此必须在启动 Go backend 前调用，并验证三层同 PID。
- 本机相邻工程 `ArkWarden` 使用 DevEco 6.1.1/Hvigor 当前格式，可复用根配置形状，避免从旧文档拼装。
- DevEco 自带 Native C++ 模板只需要一个 Node-API shared library 和 `libace_napi.z.so`，首版无需额外 C++ 框架。
- DevEco SDK 自带映射确认 API 22 的版本字符串为 `6.0.2(22)`；根产品可用 target `6.1.1(24)`、compatible `6.0.2(22)`。
- 当前 Native C++ 模板通过模块 `externalNativeOptions` 指向 CMake，并用本地类型包声明 `.so`；只保留 `arm64-v8a`，不生成 x86_64。
- 当前 fnm 环境提供 Node `v24.15.0`、npm `11.12.1`、pnpm `10.34.5`。
- DevEco 的 `hvigorw` wrapper 固定 pnpm `10.28.2` 且只认自身 wrapper 路径，没有发现外部 pnpm 路径参数；应按用户要求直接用 fnm pnpm 调用随 DevEco 安装的 Hvigor engine。
- DevEco 内置 Hvigor engine `6.24.4` 可由当前 fnm Node 直接启动；wrapper 主要额外负责依赖安装及将内置 `@ohos/hvigor`、`@ohos/hvigor-ohos-plugin` 链接到 workspace。
- 直启内置 plugin 时 Node 会按真实路径解析符号链接，需要把项目 `node_modules` 显式加入 `NODE_PATH`，才能让 plugin 反向找到 `@ohos/hvigor`。
- DevEco Studio 自带 JBR 位于 `/Applications/DevEco-Studio.app/Contents/jbr/Contents/Home`，可作为无系统 Java 环境下的 HAP 打包运行时。
- `pnpm run build:hap` 已成功生成 arm64 未签名 HAP；原生桥产物是 AArch64 ELF shared object，DevEco 链路无需联网。
- 当前沙箱不能访问 Rancher Desktop 的 Docker socket，策略也拒绝只读提升；这不代表 daemon 未启动，只能将容器实跑保持为待验证项。
- HDC 当前无法连接 server/设备，所有真机门禁保持 pending。
- 临时研究缓存含 Tailscale Android `main` 的 `libtailscale` 源码，但其核心依赖是 2026 年的 `v1.103.0-pre`，不能替代已固定的 v1.82.5 P0 输入，只能用于结构参考。
- 当前 macOS PATH 中没有系统 Go；P0 必须由锁定的 SIG Go 工具链在 linux/amd64 builder 内完成。
- 已将 SIG Go 固定提交从本轮可信临时缓存复制到忽略的 `third_party/ohos_golang_go`；Tailscale v1.82.5 的网络下载被环境策略拒绝。
- 常用本机 Go module/cache 与 `/private/tmp` 中没有固定 v1.82.5 Tailscale core 的可复用副本；只有版本不匹配的 Tailscale Android 源码。
- 生成的 HAP 确实打包了 `libs/arm64-v8a/libarkscale_bridge.so`，其动态符号表包含 Node-API 注册入口 `RegisterArkScaleBridgeModule`。
- DevEco 自带 OHOS Clang 是 Mach-O arm64；用户常用目录也未发现 Linux OHOS SDK 归档，因此 P0 builder 的 SDK 输入仍缺失。
- HAP 内 `module.json`/`pack.info` 实际记录 bundle `com.arkscale.client`、compatible API 22、target API 24、compile SDK `6.1.1.125`，与设计基线一致。
- 续跑再次扫描 Homebrew/用户缓存、Downloads 与 `/private/tmp`：没有 v1.82.5 commit 或源码归档可复用；仍只有版本不匹配的 Tailscale Android checkout。
- 用户提供的 Linux SDK Clang 已验证为 ELF 64-bit x86-64；Rancher Desktop 成功构建并启动 P0 容器。
- 当前失败发生在容器内完整克隆 Tailscale：HTTP/2 stream 被取消，继而 `early EOF`。固定 v1.82.5 tag 不需要完整仓库历史，浅克隆是更小的正确传输。
- `fetch-deps.sh` 当前确实无条件执行完整 `git clone`；失败后 `third_party/tailscale` 不存在，修复无需清理残留 checkout。
- 依赖脚本现只对 Tailscale 使用 `--depth 1 --single-branch --branch v1.82.5`；仍以固定 SHA 二次校验，未用浮动 tag 替代版本锁定。
- 浅克隆容器复验成功，Tailscale checkout 为精确 commit `e4d64c6...`。
- 新故障发生在 `/usr/local/go` bootstrap 编译 SIG Go `cmd/dist` 时：host Go runtime 的 `sysmon` 在 `runtime.netpoll_epoll` SIGSEGV；尚未证明是 SIG Go 源码还是 Apple Silicon 上 linux/amd64 仿真层。
- 当前两个固定源码目录均已成功落盘且工作树干净：OpenHarmony-SIG Go 为 `2d8b23f6923100d8c90d8add9299da2c9d032a20`，Tailscale 为 `e4d64c6faf827a308ec20b39651225178e6743c0`。
- P0 Docker 构建显式使用 `--platform linux/amd64`；若宿主机是 Apple Silicon，`/usr/local/go/bin/go` 和后续 bootstrap 工具都会经由 amd64 模拟层运行。
- 已检索仓库内 SIG Go 文档，未找到其明确支持 Darwin/arm64 作为构建宿主的依据；在取得证据前不把容器直接改成 arm64。
- 本机确认为 Apple Silicon（`arm64`）、macOS 26.3.1；Rancher Desktop client 为 1.22.3。沙箱无权读取其 daemon settings，尚需用户确认 VM type 与 Rosetta 开关。
- Rancher Desktop 上游 issue #5755 记录了 Apple Silicon 上 `linux/amd64` Go 编译间歇性 segmentation fault，且报告者说明同样构建在 Docker Desktop 不复现：https://github.com/rancher-sandbox/rancher-desktop/issues/5755
- Rancher Desktop 官方文档说明 VZ 使用 Apple Virtualization Framework，并且仅在 VZ 下可启用 Rosetta 来运行 Apple Silicon 上的 x86_64 指令：https://docs.rancherdesktop.io/ui/preferences/virtual-machine/emulation/
- 截至 2026-08-02，Rancher Desktop 最新 release 为 1.24.0，而本机是 1.22.3；版本落后本身不是本次崩溃的直接证明，只作为排障变量记录：https://github.com/rancher-sandbox/rancher-desktop/releases/tag/v1.24.0
- 本机 `rdctl set --help` 确认 1.22.3 提供 `--virtual-machine.type`（`qemu|vz`）与 `--virtual-machine.use-rosetta`；可先只读查询，再由用户决定是否让 Rancher Desktop 重启应用设置。
- 独立 Go 探针尚未启动：Rancher Desktop 拉取 `golang:1.24.5-bookworm` blob 时 CloudFront 返回 EOF。P0 此前已构建并运行 `arkscale-p0:go1.24.5`，可直接复用该本地镜像，避免把网络故障混入 SIGSEGV 诊断。
- 用户使用本地 P0 镜像完成 20 次 `go list std` 探针：`linux/amd64`、Go 1.24.5，结果 `PASS`。这排除了“官方 Go 在当前模拟层下轻负载必然崩溃”，但没有排除重编译负载下的并发/随机模拟故障。
- 失败后的 SIG Go checkout 中不存在 `bin/go` 或 `src/cmd/dist/dist`，且工作树无修改；残留二进制损坏不是当前首要假设。
- 同一 SIG Go bootstrap 在唯一变量改为 `GOMAXPROCS=1` 后完整成功，安装 Go 1.24.5 linux/amd64 host toolchain；因此当前可操作根因是 Apple Silicon 上 amd64 模拟路径的并发编译不稳定，而不是 SIG Go checkout 或 bootstrap 版本错误。
- 所有 P0 Go 命令都经 `scripts/p0-container.sh`；在该共享入口默认串行化是最小修复，原生 x86_64 环境可直接设置标准 `GOMAXPROCS` 覆盖。
- 串行修复生效后，完整 P0 稳定越过工具链阶段并开始解析 Tailscale 闭包；所有新错误均为连接 `proxy.golang.org:443` 的 `i/o timeout`，尚未出现 OpenHarmony 编译错误。
- Go 官方 module 文档确认 `GOPROXY` 可配置多个代理；逗号只在 404/410 时回退，竖线会在 timeout 等任意错误后回退：https://go.dev/ref/mod
- Goproxy.cn 当前提供 Go module proxy 与 sum.golang.org checksum database 代理，并给出 `GOPROXY=https://goproxy.cn,direct` 用法；在采用为项目默认前仍需从用户的 Rancher 容器做单模块连通性验证：https://goproxy.cn/
- 用户容器通过 `goproxy.cn` 成功下载固定 `go4.org/mem` module，返回 zip 路径、`Sum` 与 `GoModSum` 并打印 `PASS`；Google module proxy 路由故障假设成立，Rancher 全局 HTTPS 故障被排除。
- `scripts/build-p0-docker.sh` 在容器边界传入 `GOPROXY=${GOPROXY:-https://goproxy.cn,direct}`，因此默认值适配当前网络且调用者可用 Go 标准变量覆盖；未设置 `GOSUMDB=off`。
- 完整 P0 已通过：产物 `build/arm64-v8a/libarkscale_engine.so` 为约 28 MiB 的 ELF64/AArch64 shared object，`NEEDED` 只有 `libc.so`，最终脚本输出 `P0 engine verification passed`。
- P0 原先只固定 `golang:1.24.5-bookworm` 标签，不能抵抗标签漂移；现固定 Docker Official Images 返回的 linux/amd64 manifest digest，并提升本地 builder 标签以强制重建。固定 digest 的完整 P0、ELF/ABI 与合规包生成门禁通过。
- Linux SDK 的 `native/oh-uni-package.json` 明确报告 API 24；P0 入口现于 Docker 前同时校验该元数据与 x86_64 ELF Clang。合成 API 23 SDK 被预期拒绝，真实 API 24 SDK 的完整 P0 通过。
- 仅检查依赖 HEAD commit 会漏过本地源码漂移；`fetch-deps.sh` 现校验应用补丁后的完整 tracked diff hash，并拒绝非忽略的未跟踪文件。额外 Tailscale 文件与已登记文件上的额外修改两类负例均被拒绝，恢复后完整 P0 通过。
- 缓存的 SIG Go 工具链此前只要求可执行；现同时要求精确输出 `go version go1.24.5 linux/amd64`，避免复用明显不匹配的编译器。
- 尾部 `error: write on a pipe with no reader` 不是产物错误；宿主使用同类 OHOS `llvm-readelf --dyn-syms | grep -q` 对六个符号均稳定复现。`grep -q` 命中后提前退出，producer 收到 EPIPE。避免早退并复用动态符号表即可消除噪声。
- 修复后 engine 与 HAP 校验均在宿主实跑通过且无 SIGPIPE 噪声；同类 `llvm-* | grep -q` sibling 已清除。
- 设计中的 Linux build-tag 自动扫描和运行时隔离属于 P3 backend 门禁；P0 已以固定闭包成功产出并校验 `.so`，无需为了尚未运行的 backend 提前 fork Tailscale。
- 当前 HAP bridge 只有一个 `getVersion()` Node-API 函数，CMake 只链接 `libace_napi.z.so`；P1 可在这一现有 seam 直接导入最小 Go `.so` 并增加一个同步 smoke 调用，无需新建 addon 或抽象层。
- P1 smoke library 不引用 Tailscale，只验证 SIG Go 的 c-shared 加载与基础 runtime 行为；CMake 将它作为 imported shared library 链入现有 bridge，HAP 校验同时检查两个 AArch64 ELF、导出符号和 `DT_NEEDED`。
- P1 容器沿用 P0 的非 root UID，因此必须显式使用 workspace 内的 `GOCACHE`、`GOMODCACHE` 和 `GOPATH`；否则 Go 可能尝试写镜像用户目录。
- Go 默认 `-buildvcs=auto` 会为 main package 查询所在仓库；P1 的 bind-mounted 父仓库查询返回 128。ArkScale 已在构建前单独验证 SIG Go/Tailscale 固定提交，本地 engine/smoke 产物不需要嵌入父仓库状态，因此两个 build 入口统一使用 `-buildvcs=false`。
- P1 首次完整 HAP 构建通过，但 packaged bridge 的 dynamic section 含指向 `entry/libs/arm64-v8a` 的宿主绝对 `RUNPATH`。同目录 native libraries 由 HAP loader 解析，不应携带 build-tree 路径；HAP 验证必须拒绝任意 RPATH/RUNPATH。
- 链接命令确认绝对 RUNPATH 由 CMake 对 imported shared library 自动生成，并非 Go library 或 strip 阶段引入；bridge target 设置 `SKIP_BUILD_RPATH` 后链接参数、packaged ELF 和 HAP 门禁均恢复干净。
- 用户终端已通过 HDC 识别目标真机 `5NC0226529000198`。当前命令行产物为 unsigned HAP，首次真机加载应先由 DevEco 配置调试签名并 Run，确认 c-shared runtime 能加载后再增加更重的 P1 测试。
- 目标真机已显示 `Go smoke: PASS`，证明当前 SIG Go c-shared 能由 HAP/Node-API 加载，并完成同步函数、goroutine、channel、timer 和 GC 基础路径。
- P1 的“100 次启停”用 smoke library 内一个最小 worker 实现：start 创建并同步等待 goroutine 就绪，stop 关闭 channel 并等待退出，互斥状态拒绝重复 start/stop；Node-API 在一次页面加载中执行 100 对调用。
- 同一目标真机已显示 `100 start/stop cycles: PASS`。30 分钟门禁复用该 worker，增加 100 ms Go ticker 和固定大小内存活动；ArkTS 用 wall clock 显示进度、到时自动 stop，页面提前退出也会 stop，避免测试 goroutine 残留。
- 30 分钟 UI 和 N-API 已在本地签名 HAP 中编译通过；由于宿主不能执行 Linux SIG Go，必须由 `build:p1` 重新生成 smoke `.so`，不能把仅重跑 `build:hap` 当作 Go ticker 已更新。
- SDK API 24 的 `Window.setWindowKeepScreenOn()` 自 API 11 起可用，适合 P1 前台 soak；旧的 `@system.brightness.setKeepScreenOn()` 已废弃，不采用。
- 熄屏或进入后台可能挂起普通前台应用和 ArkTS timer。P1 不能只用 `Date.now()` 判定：测试期间保持主窗口亮屏，并要求 Go worker 的 100 ms ticker 至少累计 17000 次，才能把连续运行与墙上经过时间同时纳入 PASS。
- 目标真机最终显示 `30 min soak: PASS (30m 0s)`，证明该设备上 SIG Go c-shared worker 在保持前台亮屏时通过 30 分钟墙上时间与 Go tick 联合门禁；P1 已完成。
- 本机 API 24 SDK 类型定义再次确认：`startVpnExtensionAbility`、`VpnConnection.create/destroy` 自 API 11 可用，`protectProcessNet()` 自 API 22 可用且只保护调用后创建的当前进程 socket；P2 必须保持 protect-before-Go 的顺序。
- `VpnConfig.addresses` 必填，`RouteInfo` 需要 interface/destination/gateway/hasGateway/isDefaultRoute；P2 使用显式、窄范围的测试网段，不能用空 routes，以免平台按地址族补成默认全隧道路由。
- P2 首次真机 UI 只见 `IDLE sameProcess=N/A`，现有单字段轮询会覆盖 `startVpnExtensionAbility` 的结果，且 Native 全局变量不能作为跨 ArkTS runtime 的唯一诊断通道；使用应用内 common event 单向上报 Extension 阶段/PID，可同时区分未启动、API 失败和 Native 实例隔离。
- Mate X7 真机日志证明 VPN Extension 即使 manifest 未声明额外 process，也由系统启动为 `com.arkscale.client:vpn` 独立进程。进程级保护仍有效，但 Go engine/Native bridge 必须由 Extension 在该 VPN 进程内启动；UI 需通过跨进程事件/IPC 控制，不能依赖 UI 进程的 Native 全局状态。
- CommonEvent publish 成功时回调的 error 在该真机上为 null，尽管 SDK 类型未体现 nullable；直接读取 `error.code` 会导致 VPN 进程 TypeError 退出，必须使用空值安全访问。

## 技术决策
| 决策 | 理由 |
|------|------|
| Go 数据面直接读写 `dup()` 后的 TUN FD | 避免逐包跨 Node-API，明确 FD 所有权 |
| Node-API + 稳定 C ABI | 不引入 ClashBox 使用的第三方 Go N-API 封装 |
| 第三方源码由脚本按 commit 拉取 | 比提交 vendor 或 submodule 更小、更易复现 |
| 所有阶段写入同一验证记录 | 避免每阶段增加一份文档 |

## 遇到的问题
| 问题 | 解决方案 |
|------|---------|
| Linux OHOS Native SDK 尚未定位 | 阶段 0 先确认官方 SDK 获取/挂载方式；缺失则作为明确环境阻塞 |
| Rancher Desktop 无法由自动化启动 | 用户手动启动；其余本地实现继续推进 |
| 沙箱无法读取 Rancher Desktop daemon settings | 由用户运行只读 `rdctl list-settings` 或在 GUI 核对 VZ/Rosetta |
| Hvigor wrapper 尝试从 npmmirror 下载固定 pnpm，沙箱网络拒绝 | 不再使用 wrapper 下载链路，改由当前 fnm pnpm 驱动内置 engine |
| all-in-one Hvigor 的 `DEVECO_SDK_HOME` 应指向 `.../Contents/sdk`，而不是 `.../sdk/default` | 已配置 DevEco 内置 JBR，CMake、Ninja、ArkTS 与 HAP 打包均通过 |

## 资源
- `docs/design.md`
- `docs/implementation-research.md`
- `/Applications/DevEco-Studio.app/Contents/sdk/default/openharmony`

## 视觉/浏览器发现
- 固定 Tailscale tag 的网页读取未返回内容；不据此引入新的源码假设，P0 以实际 checkout 为准。

## P2 真机停止阶段诊断（2026-08-03）

- Start 真机门禁已通过：Extension 运行在独立 `:vpn` 进程，`protectProcessNet()`、TUN fd 复制以及同进程 native 校验均为 PASS。
- Stop 当前只收到 `ON_DESTROY`，没有 `STOPPED` / `dupOwnership=PASS`。根因是 UI 先调用 `stopVpnExtensionAbility()`，系统进入同步 `onDestroy()` 后直接回收 VPN 进程；`onDestroy()` 中未被等待的异步 `connection.destroy()` 与最终状态发布来不及完成。
- 修复方向：增加 UI → VPN Extension 的停止命令事件。Extension 先销毁系统持有的原始 TUN fd，再由 native 校验复制 fd 仍有效并关闭它，发布 `STOPPED ... dupOwnership=PASS`；UI 收到该状态后才停止 Extension。
- 修复后真机显示 `STOPPED dupOwnership=PASS sameProcess=PASS`，证明两阶段停止握手和复制 fd 所有权门禁通过。
- 本机 API 22 SDK 明确支持 `Text.copyOption(CopyOptions.LocalDevice)`，可让一整块诊断文本长按选择并复制到设备剪贴板。
- API 22 本地 SDK 的 `connection.createNetConnection()` 支持默认网络 `netCapabilitiesChange` 监听，所需 `GET_NETWORK_INFO` 是 normal/system-grant 权限；OpenHarmony 官方网络重连实践也以该事件识别 Wi-Fi/蜂窝默认网络变化：https://gitee.com/openharmony/communication_netmanager_base/wikis/pages/export?doc_id=3234573&type=pdf
- P2 只记录 Wi-Fi 与蜂窝 bearer 的实际变化，忽略 VPN/其他 bearer，避免 TUN 创建后把 VPN 自身误报为网络切换。
- Mate X7 真机完成 Wi-Fi → 蜂窝 → Wi-Fi 双向切换，最终显示 `SWITCH PASS CELLULAR->WIFI ... switches=2`；VPN 进程 PID、protect 和 TUN dup 状态全程保持 PASS，P2 完成。

## P3 Linux 平台路径审计（2026-08-03）

- 实际 engine 入口是 `engine/cmd/arkscale/main.go`；`engine/arkscale_engine.go` 不存在。
- P0 的 `go.mod` 已引入完整 `tailscale.com` 闭包，因此 Linux netlink/iptables 等模块出现在依赖或产物中不等于运行时会执行。P3 审计必须从 engine 入口追到构造点，并同时检查 build-tag 选择结果和运行时 factory。
- 固定 Tailscale checkout 中待审计的首要平台目录是 `net/netns`、`net/netmon` 与 `wgengine/router`；SIG Go 的 `GOOS=openharmony` 兼容行为可能额外启用 `linux` build tag。
- SIG Go 源码确认 `go/build.matchTag` 在 `GOOS=openharmony` 时把 `linux` 判为匹配，因而 `*_linux.go` 与 `//go:build linux` 会被选入；其 `internal/goos.GOOS` 还被生成成字符串 `"linux"`。所以运行时 `runtime.GOOS == "linux"` 分支也会进入 Linux 路径。
- 当前 engine 仅 blank-import `ipnlocal` 与 `wgengine`，P0 编译没有构造 backend/router/netmon；Linux 符号存在不能证明已执行。P3 接入构造函数前必须先隔离 factory。
- `net/netns/netns_linux.go` 会在 dial/listen control 中尝试 `SO_MARK` 或 `SO_BINDTODEVICE`；OpenHarmony 已由 `protectProcessNet()` 提供进程级绕行，应改选 no-op control。
- `net/netmon/netmon_linux.go` 与 `interfaces_linux.go` 会使用 rtnetlink、`/proc/net/route` 和 Linux syscall；OpenHarmony 应改用 polling monitor，并由 ArkTS 网络事件主动触发重绑。
- `wgengine/router/router_linux.go` 会构造 Linux router 并探测 policy routing/netfilter；OpenHarmony 必须改用只上报 `router.Config` 的平台 router，不能触碰系统 iptables/netlink。
- Tailscale 已有 `router.CallbackRouter`，它同时实现 `router.Router` 和 `dns.OSConfigurator`，正是把路由/DNS 配置上送平台的现成 seam；ArkScale 应直接构造它，不新增 router abstraction，也不调用 `router.New`。
- 排除 `netns_linux.go` 后仍需 OpenHarmony 文件提供 `UseSocketMark() == false`，因为被 SIG Go 选中的 `magicsock_linux.go` 会引用该符号；返回 false 也会让 opt-in raw-disco 路径在创建 AF_PACKET 前安全退出。
- `netmon` 已有 `newPollingMon` 和通用 polling 实现；最小补丁应让 OpenHarmony 选择它，并排除 `netmon_linux.go`/`interfaces_linux.go`，而不是复制 monitor 主体。
- `netmon.Monitor` 已公开 `InjectEvent()`：非 static monitor 会重新采集接口状态并触发 backend/engine 的既有 change callbacks。ArkScale 的 `arkscale_network_changed()` 可直接调用它，不需要自建 Go 事件总线。
- `wgengine.Config` 允许显式传入 `Tun`、`Router`、`DNS`、`NetMon` 与 `Dialer`。只要 ArkScale 全部提供，`NewUserspaceEngine` 不会调用默认 Linux router/DNS factory；`CallbackRouter` 可同时填充 Router 与 DNS。
- `ipnlocal.NewLocalBackend` 从 `tsd.System` 取得 engine、state store、dialer、MagicSock 和 NetMon；P3 后续应仿照 `tailscaled` 的最小组装顺序，但不复用其 `tryEngine`，因为后者会直接调用 `tstun.New`、`router.New` 和 OS DNS factory。
- 审计扩展发现 `magicsock`、`tstun`、`routetable`、`ktimeout`、DNS manager、LocalBackend SSH/autoupdate 等也会因 `linux` tag 或 `runtime.GOOS == "linux"` 进入 Linux 路径。首个补丁先隔离启动主链必经的 netns/netmon/router；其余命中必须在 backend 真正调用前逐项标记“采用/排除/替换”。
- `magicsock` 已有 `magicsock_default.go`、`batching_conn_default.go` 与 `peermtu_stubs.go`；OpenHarmony 可复用这些 portable stubs，避免 AF_PACKET/BPF、Linux UDP batching 与 peer-MTU sockopt。
- `fetch-deps.sh` 在 checkout 已处于固定 commit 时允许工作树有可重放 patch；可新增幂等 `git apply --check`/反向检查，而不重置或覆盖用户数据。
- OpenHarmony-SIG Go 会令 Tailscale 看到 `runtime.GOOS == "linux"`；因此不能依赖 `version.IsMobile()`，它只识别 Android/iOS。需要用 `openharmony` 构建标签建立平台边界，路由收敛则由 ArkScale 显式选择 `router.ConsolidatingRoutes`（如后续确有需要）。
- `wgengine.NewUserspaceEngine` 即使收到外部 `tun.Device` 也会调用 `tstun.Wrap`。OpenHarmony 必须选择便携的 `wrap_noop.go`，避免 Linux GRO/GSO 探测。
- ArkScale 不能调用 `tstun.New`：它会进入 wireguard-go 的系统 TUN 创建和 Linux 诊断路径。P3 应以 Harmony VPN 提供并复制后的 TUN fd 实现一个最小 `tun.Device` 适配器。
- `tun.Device` 的最小方法面可从 Tailscale 的 `fakeTUN` 看出：`File`、`Close`、`Read`、`Write`、`Flush`、`MTU`、`Name`、`Events`、`BatchSize`；正式实现前仍需对照当前 pinned wireguard-go 接口确认。
- 当前 C ABI 已包含 `arkscale_engine_set_tun` 与 `arkscale_engine_network_changed`，足以承载后续外部 TUN fd 注入和 `netmon.Monitor.InjectEvent()`，无需扩展 ABI 才能开始平台隔离。
- pinned Tailscale 的 Linux 专用文件有一部分仅靠 `_linux.go` 文件名选择、没有显式 build tag（`router_linux.go`、`magicsock_linux.go`、`batching_conn_linux.go`、`tstun/linkattrs_linux.go`、`tstun/wrap_linux.go`、`tstun/tun_linux.go`）。OpenHarmony-SIG Go 会选中它们，必须同时修改 Linux 文件与对应 portable 文件的 build constraint。
- 可直接复用的 portable 实现已存在：`magicsock_default.go`、`batching_conn_default.go`、`peermtu_stubs.go`、`tstun/linkattrs_notlinux.go`、`tstun/wrap_noop.go`。平台补丁只需调整选择条件，不应复制实现。
- OpenHarmony 的 `netns` 需要一个极小专用文件：复用 default no-op control，并补齐 Linux 调用方所需的 `UseSocketMark() false`。这与 VPN 扩展已调用 `protectProcessNet()` 的职责边界一致。
- 平台隔离补丁必须可重放且幂等；`fetch-deps.sh` 在确认 pinned commit 后用 `git apply --check` / `git apply --reverse --check` 应用。容器构建应在编译前运行 `go list` 审计实际选中的平台文件。
- `build-engine.sh` 已集中定义 OpenHarmony 的 Go/CGO/CC/CXX/AR 环境；平台文件审计应复用相同的 `GOOS=openharmony GOARCH=arm64` 与 pinned SIG Go，不另造工具链入口。
- `router_default.go` 已提供安全的 unsupported-OS 错误与空清理实现。让 OpenHarmony 选择它即可使意外调用 `router.New` 明确失败；正常引擎路径应显式注入 `router.CallbackRouter`。
- P3 最小 backend 组装顺序已由 pinned 源码确认：创建 `tsd.System`、持久化 `StateStore`、`netmon.Monitor`、`tsdial.Dialer`、`router.CallbackRouter`，再用显式 `wgengine.Config{Tun, Router, DNS, NetMon, Dialer, SetSubsystem, HealthTracker, Metrics, ControlKnobs}` 构造 engine，最后 `ipnlocal.NewLocalBackend` 与 `Start`。
- `wgengine.NewUserspaceEngine` 会包装并接管传入的 `tun.Device`，启动 WireGuard、router 和 netmon；其 `SetSubsystem` 会把 wrapper、MagicSock、DNS manager、Router、Dialer、NetMon 写入同一个 `tsd.System`。因此 engine 需要持有稳定的 `tun.Device`，不能直接替换其对象。
- `router.CallbackRouter` 已合并 Router 与 DNS 配置，并通过 `SetBoth` 一次上送路由、DNS 与首次 MTU，正适合 Harmony VPN 的整包重配置模型；无需自建 router/dns 类型。
- `LocalBackend` 硬依赖 System 中的 Engine、StateStore、Dialer（且 Dialer 已绑定 NetMon）和 MagicSock；交互登录通过 `SetNotifyCallback` 接收 `BrowseToURL`，然后调用 `StartLoginInteractive`，无需 localapi/ipnserver。
- Tailscale Android `1.82.4`（最接近当前 core `1.82.5` 的官方 Android 标签）已提供稳定 `multiTUN`：engine 始终持有同一个设备，平台每次建好静态配置的新 TUN 后只替换底层 `tun.Device`。Harmony 应复用这一模式，不重启 backend。
- Mate X7 真机已完成官方交互式登录，LocalBackend 进入 `Running`，`router.Config` / `dns.OSConfig` 触发 `configGen=1` 的 Harmony TUN 创建，Native 显示 `protected/tunDup/engineTun/sameProcess` 全部 PASS。
- CommonEvent 不是状态存储；浏览器前台期间 UI 会错过瞬时 `RUNNING`/`READY`。Extension 需保留最小状态快照，并在页面重新显示时响应 `STATUS` 请求。
- 覆盖安装后的首次重启无需再次登录，证明当前 FileStore 应用私有目录路径可持久化 Tailscale 身份状态；停止路径也已收敛为显式 `Backend: STOPPED` 快照。

## P4 peer 与 DERP 数据面（2026-08-03）

- `hdc shell ping` 来自系统 shell，不经过 ArkScale 应用 VPN，不能作为全设备 VPN 数据面门禁；探针必须从应用 VPN 路径内部发起。
- LocalBackend 的 TSMP 可验证到 peer 的 WireGuard/IP 数据面，Disco 可独立报告直连 endpoint 或 DERP region；两者组合足以验证当前路径而不假设 peer 开放某个 TCP 端口。
- pinned Tailscale 的 `LocalBackend.Ping` 会在进入自身 context select 前同步调用 engine Ping；调用侧需设置独立 deadline，避免异常网络状态阻塞整个 VPN 停止流程。
- `wgengine.NewUserspaceEngine` 构造 wrapper 后不会替平台自动启动外部 TUN；官方 `tailscaled` 和 `tsnet` 都会调用 `sys.Tun.Get().Start()`。遗漏该调用时 Disco/control 可用，但 `tstun.Wrapper.Read()` 会阻塞在 `awaitStart()`，表现为 TSMP 无握手且发送计数为零。
- Mate X7 到 alpine `100.127.64.12` 的 TSMP 最终为 `PASS 77.3ms`，Disco 路径为 `derp myderp`；结合用户确认 region 900 已恢复，可确认自建 DERP 900 承载的数据路径可用。该次结果单独不证明直连、TCP、MagicDNS 或 IPv6；后续门禁已分别补齐。
- 物理网络没有公网 IPv6 不阻止 Tailscale ULA：peer 到手机的 IPv4/IPv6 TSMP 均可经 DERP 往返，最终干净构建也同时通过 IPv6 TSMP 与 Harmony 原生 TCP。
- Go 配置与 Harmony NetManager 属性都包含 IPv6 地址和路由；`ifconfig` 未显示、`isIPv6LinkValid=false` 不能据此判断 VPN ULA 路由缺失，后者面向可用的全局/默认 IPv6 链路。
- Harmony `NetAddress.family` 省略时默认 IPv4，IPv6 TCP 目标必须显式设为 `2`。连接返回的 `2301101` 对应本机 `ENETUNREACH`，不是 peer 或 DERP 超时。
- IPv6 路由的根因是 `hasGateway=false` 时仍传入非空 `gateway.address='::'`；目标系统会继续把它当作 next-hop。改为空字符串后无需显式 source bind，IPv6 TSMP 与 TCP 均通过。

## P4 控制面配置重建（2026-08-04）

- pinned `router.CallbackRouter` 会分别比较 route 与 DNS 配置，只在实际变化时调用 `SetBoth`；因此递增的 `configGen` 可作为有效配置变化证据，不需要另造配置 hash。
- MagicDNS 关闭时 DNS/search 数量从 `1/1` 变为 `0/0`，恢复后回到 `1/1`；两次变化都完成新 TUN 接管。恢复后的首次探针曾回填短名，手工 FQDN 已可解析；后续新进程的探针自动回填 FQDN 并通过，因此没有为未稳定复现的短名状态增加补丁。
- 批准一条临时子网路由后 route 数量从 9 增至 10，撤销后恢复为 9；两次变化都递增 generation，并保持 `tunDup/engineTun/sameProcess` 为 PASS。
- 临时路由增加与恢复后，peer TSMP、Harmony 原生 TCP 和 MagicDNS 都重新通过；P4 控制面变化门禁完成。
- alpine 测试端报告 CLI 与 daemon 版本不一致。它未阻塞 P4，但进入 P5 长稳前应先对齐版本，避免把 peer 环境差异混入稳定性结论。

## P5 短时资源稳定性（2026-08-04）

- CommonEvent 跨进程传输在当前真机持续增长 FD，已改为应用私有 EL1 文件上的四槽共享 mmap mailbox；每槽单写者、latest-only，Node-API watcher 仅在序号变化时通知 ArkTS。
- 修复前 30 秒 socket 从 192 增至 724，新增 532 个全部是未连接 IPv4 UDP；peer 探针调用本身不增长，排除了探针请求路径。
- 根因位于固定 OpenHarmony-SIG Go 的 `src/net/interface_table_openharmony.go`：两条接口枚举路径都未关闭 ioctl socket，也未释放 `getifaddrs` 结果。补丁在共享实现一次修复所有调用方，不改 Tailscale 的正常 NetMon 轮询。
- 清理版真机 30 秒前后 FD `47→46`、RSS `188552→188756 KB`，两次 peer 探针均通过，线程与 goroutine 回落；短时资源门禁通过，24 小时长稳仍待执行。
- 清理版 Stop 显示 Backend、Extension 与 Native 全部停止，`dupOwnership/engineTun/sameProcess` 均通过；随后以新 VPN 进程启动，动态配置恢复，`protected/tunDup/engineTun/sameProcess` 与 Backend RUNNING 均通过。
- 从最近任务划掉并重开 UI 后，独立 VPN 进程保持原 PID 和连续 uptime，页面通过共享状态通道恢复 READY/RUNNING；peer 继续通过且 FD 保持 46。
- 系统强制停止后页面状态干净归零；重新 Start 创建新 VPN 进程，无需再次登录即可恢复动态配置、Backend RUNNING 和 peer 数据面，FD 保持 46。
- 飞行模式往返后同一 VPN 进程保持 READY/RUNNING，默认网络 netId 与 switch 计数按预期变化；peer、原生 TCP 和 MagicDNS 全部恢复，FD 保持 46。
- 设备重启后页面状态干净归零；重新 Start 无需登录即可恢复动态配置和 Backend，peer、原生 TCP、MagicDNS 全部通过，FD 为 45。

## P5 本地安全与合规（2026-08-04）

- Tailscale FileStore 在应用私有目录以 `0600` 原子写入状态，跨进程 mailbox 也以 `0600` 创建；HAP 只声明 `INTERNET` 与 `GET_NETWORK_INFO`。
- `.env` 原先未被忽略，已补齐忽略规则；staged-secret 门禁会拒绝环境文件、签名材料及 Signing Config 密码，避免本地调试签名误入提交。
- `go list -m all` 包含 Tailscale 的 lint、测试和发布工具，不代表 engine 运行时闭包；SBOM 必须用 `GOOS=openharmony GOARCH=arm64` 的 `go list -deps` 生成。
- 最终 SPDX 包含 52 个实际 Go 依赖模块，许可证 manifest 有 55 条第三方原文映射；未发现缺失的模块许可证文件。
- 用户确认 ArkScale 采用 MIT 许可证，版权主体登记为 `ArkScale contributors`；SPDX 与许可证原文包同步声明 MIT，第三方依赖仍保留各自许可证。
- 首版设备矩阵只登记完成端到端门禁的 Mate X7，并显式保留其他 API 22+ 型号、24 小时长稳、低内存与 release 分发空白；单设备结果不外推为全面兼容。
- 52 个运行时 Go 模块的许可证技术归类为：23 个 Apache-2.0、19 个 BSD-3-Clause、7 个 MIT、2 个 BSD-2-Clause，以及 1 个 `Apache-2.0 AND BSD-3-Clause`；P0 同时归档 NOTICE/PATENTS，并校验模块路径和版本与登记表完全一致。
- LocalBackend、NetMon、userspace engine、netstack 和 FileStore 原先共用 `log.Printf`；现统一复用 Tailscale 的 `logger.Discard`，并把启动、登录和 Notify 的底层错误固定为无敏感信息的健康消息。用户主动触发的 peer 诊断仍只在本机页面显示。
- 固定 Tailscale 提交的 `LocalBackend.Logout` 仅在控制面登出成功后删除当前 profile；ArkScale 因此保留普通 Stop 的本地身份，并新增显式 Logout。Logout 期间抑制 `NeedsLogin` 自动拉起交互登录，失败时保持 backend/VPN 运行，成功时才关闭 engine 与 VPN。
- 显式 Logout 已通过 Go 单测、P0 AArch64 构建、ArkTS/HAP 构建以及 unsigned/signed HAP ABI 校验；真机门禁会删除当前身份，尚未在未获明确同意时执行。
- Logout 属于破坏性操作，页面使用原生 `UIContext.showAlertDialog` 二次确认；取消按钮默认聚焦且允许点击遮罩取消，避免误触删除身份。
- alpine 重启 tailscale 服务后 CLI/daemon 不再报告版本不一致；后续 peer、TCP 与 MagicDNS 回归通过，测试 peer 版本门禁已对齐。
