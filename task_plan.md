# 任务计划：实现 ArkScale API 22+ 最小客户端

## 目标
按已确认的门禁顺序完成可复现的 Tailscale/OpenHarmony 编译、Go c-shared 真机、VPN/TUN、Tailscale backend 和端到端验证。

## 当前阶段
阶段 P5（in_progress：稳定性与安全）

## 各阶段

### 阶段 0：环境与仓库基线
- [x] 更新文档到 API 22+ / `protectProcessNet()` 决策
- [x] 初始化最小项目结构和忽略规则
- [x] 验证 DevEco/Hvigor/CMake/ArkTS/HAP 本地链路
- [x] 验证 Docker linux/amd64 daemon
- [x] 定位并挂载 Linux OHOS SDK
- [x] 连接 HDC 真机
- **状态：** completed

### 阶段 P0：Tailscale 依赖闭包编译
- [x] 固定并获取 OpenHarmony-SIG Go 源码
- [x] 获取固定 Tailscale v1.82.5 源码
- [x] 建立最小 engine module、构建容器和脚本
- [x] 生成并检查 AArch64 c-shared 产物
- **状态：** completed

### 阶段 P1：Go c-shared HAP 真机
- [x] 建立最小 Stage/Native 工程
- [x] 接入 Go smoke library 与 Node-API
- [x] 构建并校验含 Go smoke library 的 HAP
- [x] 使用调试签名在真机完成首次加载
- [x] 真机执行 100 次 Go worker 启停
- [x] 完成 30 分钟真机持续运行验证
- **状态：** completed

### 阶段 P2：VPN/TUN/process-protect PoC
- [x] 实现 `VpnExtensionAbility`
- [x] 在 Go 启动前调用 `protectProcessNet()`
- [x] 验证 TUN FD、`dup()` 所有权和同进程
- [x] 验证网络切换
- **状态：** completed

### 阶段 P3：Tailscale backend
- [x] 审计并隔离错误选择的 Linux 平台实现
- [x] 将 Harmony TUN fd 注入 Go c-shared 引擎并通过真机启停门禁
- [x] 接入 userspace engine 与 LocalBackend
- [x] 实现动态路由、DNS、MTU 和 TUN 重建
- [x] 实现官方 Tailscale 交互式登录与状态持久化
- **状态：** completed

### 阶段 P4：端到端网络
- [x] 验证 peer TSMP 与自建 DERP 数据路径
- [x] 验证 peer TCP、直连、MagicDNS、IPv4/IPv6
- [x] 验证 Wi-Fi/蜂窝切换
- [x] 验证控制面路由/DNS 配置变化
- **状态：** completed

### 阶段 P5：稳定性与安全
- [ ] 对齐测试 peer 的 CLI/daemon 版本
- [x] 修复跨进程事件传输与 SIG Go 接口枚举资源泄漏，完成短时真机回归
- [ ] 完成 24 小时、异常恢复和资源泄漏测试
- [ ] 生成设备矩阵
- [ ] 完成项目许可证选择与第三方许可证人工确认
- [x] 生成并验证 SPDX SBOM 与许可证原文包
- **状态：** in_progress

## 已做决策
| 决策 | 理由 |
|------|------|
| API 22+，compile SDK API 24 | 允许使用进程级 socket 保护，减少跨语言协议 |
| `com.arkscale.client` | 用户确认的 bundle name |
| 官方 Tailscale 控制面 | 首版减少 Headscale 兼容变量 |
| Docker `linux/amd64` | 符合 OpenHarmony-SIG Go 已公开的构建主机基线 |
| 阶段门禁推进 | 先暴露 runtime、ABI 与 VPN 平台风险，不先做 UI |
| P1 复用现有 Node-API bridge 并链接独立 smoke `.so` | 最小验证 Go runtime/c-shared，不引入 Tailscale 或额外封装层 |
| HAP 构建入口为 `pnpm run build:hap` | 使用当前 fnm 的 pnpm/Node，并直连 DevEco 内置 Hvigor，避免 wrapper 下载固定 pnpm |
| P1 soak 保持主窗口亮屏并校验 Go tick 数 | 防止熄屏挂起后仅凭 ArkTS 墙上时间产生假 PASS |

## 遇到的错误
| 错误 | 尝试次数 | 解决方案 |
|------|---------|---------|
| zsh 一致性扫描出现 unmatched quote | 1 | 不在双引号命令中嵌入 Markdown 反引号，改用简单固定模式 |
| 自动启动 Rancher Desktop 被权限策略拒绝 | 1 | 不绕过；继续本地工作，等待用户手动启动后再验证 Docker daemon |
| `git diff --no-index --check` 以 1 表示存在差异，被循环误判为 whitespace | 1 | 只检查命令输出，不用退出码判断 whitespace |
| Hvigor 无权创建 `~/.hvigor` 缓存，提升权限被策略拒绝 | 2 | 使用项目 `.cache/hvigor`，并直接调用 DevEco 内置 engine/plugin |
| Hvigor wrapper 固定下载 pnpm 10.28.2，沙箱网络失败且提升请求被中止 | 1 | 按用户要求使用当前 fnm 的 pnpm，直接调用 DevEco 内置 Hvigor engine |
| Docker socket 只读检查被沙箱拒绝，提升请求也被策略拒绝 | 2 | 不再重试或绕过；先完成不依赖 daemon 的 P0 工程与脚本，容器验证留作环境门禁 |
| 固定 Tailscale v1.82.5 源码下载被沙箱网络拒绝，提升请求也被策略拒绝 | 2 | 不绕过；检查可信本地缓存，若无则把真实闭包编译保留为外部环境门禁 |
| 三次连续 goal turn 均缺少 P0 外部输入 | 3 | 不跨越 P0 硬门禁；等待 Linux SDK、Docker 访问和固定 Tailscale checkout |
| 空白扫描误扫入模块 `.cxx` 生成物 | 1 | 将任意层级 `.cxx`/`.hvigor` 目录纳入忽略规则后复查源码 |
| Tailscale 完整 clone 经 HTTP/2 中途断开并报 `early EOF` | 1 | 已改成固定 tag 的浅克隆，减少传输体积并保留 commit 校验；等待容器复验 |
| 构建 SIG Go `cmd/dist` 时在 `runtime.netpoll_epoll` SIGSEGV | 1 | `GOMAXPROCS=1` 下完整 bootstrap 通过；P0 容器默认串行 Go 构建并允许原生 x86_64 覆盖 |
| 独立探针拉取 `golang:1.24.5-bookworm` 时网络 EOF | 1 | 不重复下载；改用已由 P0 构建成功的本地 `arkscale-p0:go1.24.5` 镜像 |
| engine 下载 Go modules 时连接 `proxy.golang.org:443` 超时 | 1 | `goproxy.cn` 单模块下载与哈希校验通过；P0 默认使用该代理并允许标准 `GOPROXY` 覆盖 |
| `rg` 将以 `--env` 开头的固定模式误认成选项 | 1 | 在模式前加入 `--` 后复验通过 |
| 成功校验后 `llvm-readelf` 打印 `write on a pipe with no reader` | 1 | 复现为 `grep -q` 提前关闭管道；改为完整消费输出且动态符号表只读取一次 |
| 复查旧工程模板时预期的 `/Users/yangzhitao/repos/ArkWarden` 不存在 | 1 | 不依赖外部工程；按当前工程和 Harmony CMake 原生导入规则实现 P1 |
| 宿主 Clang 直接包含 OHOS N-API 头时找不到 `bits/alltypes.h` | 1 | 改用 DevEco OHOS Clang，并显式设置 AArch64 target 和 sysroot；检查通过 |
| 自动运行 P1 时无法访问 Rancher Desktop Docker socket | 2 | 普通执行与受控提权均被当前策略拒绝；不绕过，由用户在本机终端运行同一命令 |
| P1 Go build 获取父仓库 VCS 状态时返回 128 | 1 | engine/smoke 可复现构建统一关闭无用途的 VCS stamping；固定第三方提交仍由构建前校验保证 |
| P1 bridge 携带宿主机绝对 RUNPATH | 1 | HAP 门禁新增 RPATH/RUNPATH 拒绝检查；设置 `SKIP_BUILD_RPATH` 后重建通过 |
| 自动检查 HDC 设备时无法连接本机 daemon | 2 | 沙箱内返回 `Connect server failed`，受控提权被策略拒绝；不绕过，由用户终端列出设备 |
| 本机自动读取 `hdc help` 仍等待 daemon | 1 | 不重复调用；设备已由用户 `list targets` 确认，后续真机操作由 DevEco/用户终端执行 |
| 自动创建 `dev` 分支时 `.git/HEAD.lock` 被沙箱拒绝 | 2 | 不绕过 Git 元数据权限；等待用户在本机终端执行 `git switch -c dev` |
| P2 真机只显示 `IDLE sameProcess=N/A` | 1 | 分离 UI 启动结果、Extension 生命周期事件和 Native 状态，并比较两侧 PID 后再判断根因 |
| CommonEvent `parameters` 触发 ArkTS `no-any-unknown` | 1 | 改用显式 string 类型的 `data` 字段传递 `status|pid`，不关闭严格检查 |
| VPN Extension 点击后因读取 `null.code` 闪退 | 1 | CommonEvent 成功回调的 error 实际为 null；所有回调改为可选链，并由独立 VPN 进程随事件上报其 Native 状态 |
| Stop 只上报 `ON_DESTROY`，未出现 `dupOwnership=PASS` | 1 | 不再从 UI 直接销毁 Extension；先跨进程请求 Extension 完成 TUN 销毁与 fd 所有权校验，收到 `STOPPED` 后再停止 Extension |
| P3 首次读取假设 engine 入口为 `engine/arkscale_engine.go` | 1 | 使用 `rg --files engine` 定位真实入口 `engine/cmd/arkscale/main.go`，后续从该入口追踪 |
| P3 自动读取 Docker daemon 被沙箱拒绝 | 2 | 不绕过；先用固定 SIG Go/Tailscale 源码完成静态审计，并提供容器内 `go list` 回归脚本给用户终端执行 |

## 备注
- 外部资料只写入 `findings.md`。
- 任一阶段未通过时，不进入后续阶段。
- P0 已生成并校验 AArch64 engine；当前先完成 P1 构建和真机门禁，Linux 平台实现审计保留到 P3 backend。
