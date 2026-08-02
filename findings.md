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
