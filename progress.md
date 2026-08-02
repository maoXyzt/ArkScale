# 进度日志

## 会话：2026-08-02

### 阶段 0–P1：环境基线、P0 与 P1
- **状态：** P1 in_progress
- 执行的操作：
  - 核对仓库仅含文档。
  - 确认本机 macOS arm64、DevEco API 24 SDK、HDC/Hvigor 和 Docker CLI。
  - 用户确认 API 22+、真机、Docker/Rancher、`com.arkscale.client` 和官方 Tailscale。
  - 已将 README、设计和研究报告同步为 API 22+ / `protectProcessNet()`。
  - 自动启动 Rancher Desktop 被权限策略拒绝，等待用户手动启动。
  - 找到本机 DevEco 6.1.1 工程与 Native C++ 官方模板作为最小脚手架基线。
  - 确认 API 22 版本字符串 `6.0.2(22)` 和当前 Native C++ 模块配置格式。
  - 创建 API 22+/API 24 的最小 Stage/Native C++ 工程，仅含 EntryAbility 与 `getVersion()` N-API 冒烟接口。
  - `ohpm install` 成功。
  - Hvigor 构建因无法写入 `~/.hvigor` 失败，提升权限请求也被策略拒绝。
  - 用户要求改用当前 fnm 管理的 pnpm；已确认 pnpm `10.34.5`。
  - 确认 DevEco wrapper 固定 pnpm `10.28.2`，无法配置为外部 pnpm；改为用当前 fnm pnpm 直接调用内置 Hvigor `6.24.4`。
  - 确认 DevEco 内置 JBR 可用于最后的 HAP 打包步骤。
  - 新增 `package.json` 与 `scripts/build-hap.sh`，通过当前 fnm pnpm/Node 驱动 DevEco 内置 Hvigor。
  - `pnpm run build:hap` 成功，生成 arm64 `entry-default-unsigned.hap` 与 `libarkscale_bridge.so`。
  - 复核临时 Tailscale Android 源码缓存；版本不匹配固定 core commit，未作为 P0 依赖复用。
  - 建立 P0 engine module、稳定 C ABI 头文件、固定依赖脚本、linux/amd64 Docker builder、交叉编译与 ELF/符号验证脚本。
  - 所有 shell 构建脚本通过 `sh -n`；宿主直接运行工具链脚本会按预期拒绝非 linux/amd64。
  - 从已核验的本轮临时缓存取得 SIG Go 固定提交；Tailscale v1.82.5 下载在沙箱网络和提升策略两处均被拒绝。
  - 搜索本机 Go module/source 缓存，未找到可替代下载的 v1.82.5 core checkout。
  - ShellCheck、`sh -n` 与 `pnpm run build:hap` 复验通过；P0 也暴露为当前 fnm pnpm 脚本 `pnpm run build:p0`。
  - 稳定 C ABI 头文件通过 Clang C11 `-Wall -Wextra -Werror` 语法检查；P0 脚本缺少 Linux SDK 时会在调用 Docker 前明确失败。
  - 新增 `pnpm run verify:hap`，验证 bundle/API 版本、未签名 HAP 内的 arm64 bridge 与 Node-API 注册导出；实跑通过。
  - P0 验证扩展为检查 ELF version info 中的 `GLIBC_`、RPATH/RUNPATH 和 workspace 绝对路径泄漏。
  - EntryAbility 改为处理 `loadContent` 回调错误；重新触发 ArkTS 编译后无代码警告，HAP 构建与验证再次通过。
  - 将 P0 C ABI 收紧为诚实的依赖闭包探针：真实 backend 未接入前返回 `NOT_IMPLEMENTED`，不伪报启动成功。
  - 最终 ShellCheck、shell 语法、C/C++ 头文件 warnings-as-errors 和源码空白检查通过。
  - 自动续跑已恢复规划文件；session catch-up 无未同步变更，继续核对本地可复用输入。
  - 再次扫描本机缓存与临时目录，未发现固定 Tailscale v1.82.5 源码；工作树未出现新的外部输入。
  - 用户完成 Linux x86-64 OHOS SDK 验证并成功运行 Docker P0 容器；阶段 0 的 SDK/Docker 门禁已解除。
  - P0 在完整 clone Tailscale 时因 HTTP/2 中断报 `early EOF`；进入可复现的依赖获取修复。
  - 复核失败现场：SIG Go checkout 仍为固定 commit，Tailscale 失败目录已由 Git 自动清除。
  - 将 Tailscale 获取改为 v1.82.5 浅克隆；浅克隆参数回归断言由 red 变 green，ShellCheck 与 `sh -n` 通过。
  - 用户容器复验确认浅克隆修复有效，固定 Tailscale checkout 已取得。
  - P0 推进到 SIG Go 工具链构建，bootstrap Go 在 `runtime.netpoll_epoll` 触发 SIGSEGV；进入架构/仿真诊断。
  - 用户以 `GOMAXPROCS=1` 重跑同一 SIG Go bootstrap，完整生成 linux/amd64 工具链；并发模拟故障假设得到验证。
  - `p0-container.sh` 现在默认 `GOMAXPROCS=1`，同时保留标准环境变量覆盖，覆盖工具链与 engine 的全部 Go 命令。
  - 完整 P0 已稳定越过 bootstrap，进入 engine module 下载；当前阻塞为容器连接 `proxy.golang.org:443` 超时。
  - 用户通过 `goproxy.cn` 成功下载固定 `go4.org/mem` module，并取得预期 Sum/GoModSum。
  - P0 Docker 入口现在传入可覆盖的 `GOPROXY`，默认 `https://goproxy.cn,direct`；未关闭 checksum database。
  - 完整 P0 成功生成 28 MiB AArch64 ELF shared object；动态依赖只有 `libc.so`，GLIBC/RPATH/绝对路径/C ABI 校验通过。
  - `llvm-readelf | grep -q` 的 SIGPIPE 噪声已在宿主对生成 ELF 稳定复现；engine 校验改为完整消费管道并复用一次动态符号表输出。
  - 新增不含 Tailscale 的 P1 Go smoke module，覆盖 c-shared 加载、goroutine、channel、timer、内存分配与 GC。
  - smoke `.so` 已通过现有 Node-API bridge 接入 ArkTS 页面；P1 构建脚本复用已完成的 P0 builder 和 SIG Go 工具链。
  - P1 脚本补齐容器内项目级 Go cache，避免非 root UID 写入镜像 `/root`；ShellCheck、shell 语法、C/C++ 头文件与 N-API 签名静态检查通过。
  - P1 在容器 bind mount 中因 Go 默认 VCS stamping 获取父仓库状态失败；engine/smoke 两个产物统一加入 `-buildvcs=false`，不影响已有的 SIG Go/Tailscale commit 校验。
  - 用户完成 P1 HAP 构建；本地复验确认两个 AArch64 `.so`、导出符号、`DT_NEEDED` 和 HAP 内容均存在。
  - 深入检查发现 bridge 带宿主机绝对 `RUNPATH`；`verify:hap` 已先加入拒绝 RPATH/RUNPATH 的红色回归门禁。
  - 根因是 CMake 为 imported smoke library 自动加入 build-tree rpath；bridge 设置 `SKIP_BUILD_RPATH` 后重建，HAP 验证、dynamic section 和 workspace 路径检查全部通过。
  - 自动检查 HDC 时沙箱无法连接本机 daemon，受控提权也被策略拒绝；P1 停在真机连接/签名门禁。
  - 用户终端 `hdc list targets` 返回设备 `5NC0226529000198`；阶段 0 环境门禁完成。
  - 当前 HAP 是 unsigned；P1 先通过 DevEco 调试签名完成一次真机加载，再扩展 100 次循环和 30 分钟稳定性测试。
  - 用户确认目标真机页面显示 `Go smoke: PASS`，SIG Go c-shared 首次加载、同步调用、goroutine/channel/timer/GC 通过。
  - P1 增加带互斥状态检查的 Go worker `start/stop`，页面将连续执行 100 次并显示独立结果；先验证该生命周期门禁，再增加 30 分钟持续测试。
  - 100 次生命周期改动通过 C11/C++17 ABI、OHOS N-API warnings-as-errors、ShellCheck、shell 语法和源码一致性检查。
  - 用户确认目标真机同时显示基础 smoke 与 100 次 start/stop PASS；100 次生命周期门禁通过。
  - P1 增加自动 30 分钟 soak：同一 Go worker 每 100 ms 执行 timer/内存活动，页面按真实经过时间计时，到时自动 stop 并显示 PASS；页面退出会清理 worker。
  - 30 分钟 UI/Node-API 改动通过 OHOS C++ warnings-as-errors、ShellCheck、ArkTS 编译、签名 HAP 构建与 HAP 校验；当前 HAP 仅用于接口检查，真机前仍需 `build:p1` 重建更新后的 Go `.so`。
  - 核对 API 24 SDK，主窗口正式提供 `setWindowKeepScreenOn()`；P1 soak 在页面加载后请求保持亮屏，并以至少 17000 个 Go 100 ms tick 作为 30 分钟 PASS 的附加条件。
  - 新增 tick C ABI/Node-API/类型声明及 HAP 导出符号门禁；OHOS C/C++ warnings-as-errors、ShellCheck 和 shell 语法检查通过。
  - 完整 P1 重建仍由当前会话的 Docker socket 权限阻止；用户需在终端重跑 `build:p1` 后开始真机 soak。
  - 提交前发现 DevEco 自动签名配置含本机凭据字段；已恢复为无签名的可提交基线，并忽略生成的 `.so` 和常见签名材料。
  - 创建 `dev` 分支所需的 Git 元数据写入被沙箱拒绝；等待用户执行一次 `git switch -c dev` 后继续阶段提交。
  - 用户已在本机创建并切换到 `dev`；开始按文档基线、P0 构建链、P1 真机探针记录三个阶段提交。
  - `dev` 已形成三个阶段节点：API 22 文档门禁、可复现 P0 engine 工具链、P1 HarmonyOS Go runtime 探针；工作树提交范围不含签名材料和生成产物。
  - DevEco 恢复本机签名材料后，产品未关联 `signingConfig`，首次部署报 `9568320: no signature file`；本机补回 `signingConfig: default` 后生成 signed HAP，签名字段保持未提交。
  - 用户确认目标真机显示 `30 min soak: PASS (30m 0s)`；保持亮屏、墙上时间和 Go tick 数联合门禁通过，P1 完成并进入 P2。
  - P2 第一小步已实现：声明三方 VPN Extension/INTERNET 权限，UI 启停系统 VPN 授权，Extension 严格按 protect-before-create 顺序创建单个 `/32` 测试 TUN，Native `dup()` 并上报同进程/保护/FD 状态。
  - P2 首次本机构建成功并产出 signed HAP；ArkTS 对 `destroy()` 异常收口给出警告，已改为 helper 内返回错误码，保持停止路径无未处理 Promise。
  - P2 重建无 ArkTS/C++ 警告且 HAP 基础校验通过；下一步把 VPN Extension 与 INTERNET 权限写入 HAP 回归门禁，再进行真机授权/FD 验证。
  - P2 首次真机反馈为 `VPN probe: IDLE sameProcess=N/A`，门禁未通过；当前 UI 的 500 ms Native 状态轮询会覆盖启动请求结果，无法区分 Extension 未启动与 Native 实例不共享，先补分层状态/PID 诊断再复验。
  - P2 诊断 UI 现分别显示 control、Extension common event 和 Native 状态；Extension 每个生命周期阶段上报自身 PID，UI 同时显示 PID 比较，单次真机复验可区分启动失败、生命周期未进入、跨进程和 Native 实例隔离。
  - 首次诊断构建被 ArkTS `no-any-unknown` 拒绝，因为 CommonEvent `parameters` 类型为 `any`；改用显式 string 类型的 `data` 传递 `status|pid`，保持严格类型门禁。
  - P2 分层诊断版 signed HAP 已无警告构建，HAP 验证通过；等待真机回传 Control/Extension/Native 三行以完成根因判定。
  - 真机堆栈确认 Extension 已进入 `onCreate` 和 `ProtectProcessNet`，系统自动使用 `com.arkscale.client:vpn` 独立进程；闪退根因是 CommonEvent 成功回调传入 null error，代码读取 `error.code`。
  - 修复所有 CommonEvent callback 的 null error 处理；删除无意义的 UI Native 轮询，改由 VPN 进程在事件中携带其 Native 探针状态。
  - VPN 进程闪退修复后的 signed HAP 已无 ArkTS/C++ 错误构建，HAP 与 whitespace 门禁通过；待同一真机复验。
  - 真机 Start 已通过 `process=SEPARATE`、`protected=PASS`、`tunDup=PASS`、`sameProcess=PASS`；P2 的启动/保护/复制路径成立。
  - 真机 Stop 只到 `ON_DESTROY`：UI 先销毁 Extension，导致其同步生命周期结束早于异步 `connection.destroy()` 和 native fd 校验。停止流程现改为命令事件握手，收到 `STOPPED ... dupOwnership=PASS` 后才销毁 Extension。
  - P2 状态合并成一个 ArkUI Text，并启用 `CopyOptions.LocalDevice`；真机可长按选择并复制完整诊断块。
  - 停止握手与可复制诊断版已用当前 fnm pnpm 完成 signed HAP 构建，`verify:hap` 通过；真机最终显示 `STOPPED dupOwnership=PASS sameProcess=PASS`。
  - P2 最后一个探针使用系统 `connection.createNetConnection()` 监听默认网络 bearer；UI 新增可复制的 `Network` 行，仅在 Wi-Fi 与蜂窝之间变化时显示 `SWITCH PASS`。
  - 新增 normal/system-grant 的 `GET_NETWORK_INFO` 权限及 HAP 门禁；真机完成 Wi-Fi → 蜂窝 → Wi-Fi 双向切换，显示 `SWITCH PASS CELLULAR->WIFI ... switches=2`，P2 完成。
  - P3 开始从真实 engine 入口审计固定 Tailscale v1.82.5；首批范围为 `netns`、`netmon`、`router` 的 build tags 与 factory 调用链。
  - 当前会话普通和受控权限均不能读取 Rancher Desktop daemon；P3 改为先生成可重放补丁与容器内 build-tag 审计脚本，容器实跑留给用户终端。
  - Hvigor 提示 entry module SemVer 警告，但 `0.1.0` 合法且当前不发布 ohpm 模块；不为无关发布路径扩展配置。
- 创建/修改的文件：
  - `.gitignore`
  - `README.md`
  - `docs/design.md`
  - `docs/implementation-research.md`
  - `task_plan.md`
  - `findings.md`
  - `progress.md`
  - `build-profile.json5`、`oh-package.json5`、`hvigorfile.ts`、`hvigor/`
  - `AppScope/`
  - `entry/`

## 测试结果
| 测试 | 输入 | 预期结果 | 实际结果 | 状态 |
|------|------|---------|---------|------|
| SDK 元数据 | DevEco bundled SDK | API >= 22 | API 24 / 6.1.1.125 | pass |
| ohpm 依赖安装 | 本地类型包 | 完成 | install completed | pass |
| HAP 构建 | `pnpm run build:hap` | 生成 debug HAP | `BUILD SUCCESSFUL`，生成未签名 HAP | pass |
| Native 架构 | `file libarkscale_bridge.so` | AArch64 ELF shared object | `ELF 64-bit ... ARM aarch64` | pass |
| P0 shell 静态检查 | ShellCheck + `sh -n` | 无问题 | 均通过 | pass |
| C ABI 头文件 | Clang C11/C++17 warnings-as-errors | 编译通过 | 无诊断 | pass |
| P0 SDK 输入门禁 | 未设置 `ARKSCALE_LINUX_SDK` | Docker 前失败并说明参数 | 按预期失败 | pass |
| HAP 内容验证 | `pnpm run verify:hap` | arm64 bridge 被打包且导出 N-API 注册符号 | 通过 | pass |
| HDC 设备列表 | `hdc list targets` | 至少一个设备 | 用户输出 `5NC0226529000198` | pass |
| Docker daemon | `pnpm run build:p0` | 成功构建并启动 linux/amd64 容器 | 用户输出进入容器依赖获取阶段 | pass |
| Linux OHOS Clang | `file .../native/llvm/bin/clang` | ELF x86-64 | 用户输出确认 ELF 64-bit x86-64 | pass |
| Tailscale clone 回归 | 浅克隆参数断言 + ShellCheck + `sh -n` | 使用固定 tag 浅克隆且脚本有效 | 通过 | pass |
| 固定 Tailscale checkout | 容器 `fetch-deps.sh` | commit `e4d64c6...` | 用户输出确认 | pass |
| 固定源码工作树 | `git status` / `git rev-parse HEAD` | 两个输入均固定且干净 | 通过 | pass |
| amd64 Go 轻负载探针 | 本地 P0 镜像内循环 20 次 `go list std` | 无 SIGSEGV | `PASS` | pass |
| SIG Go 串行 bootstrap | `GOMAXPROCS=1 ./scripts/build-go-toolchain.sh` | 完整安装 host toolchain | Go 1.24.5 linux/amd64 安装成功 | pass |
| P0 串行默认值静态检查 | `sh -n` + ShellCheck + debug 标记扫描 | 入口脚本有效且无遗留诊断日志 | 通过 | pass |
| Go module 代理探针 | 固定 `go4.org/mem` 版本经 `goproxy.cn` 下载 | 下载并校验成功 | JSON 含 zip、Sum、GoModSum；`PASS` | pass |
| P0 GOPROXY 接入静态检查 | `sh -n` + ShellCheck + 固定参数断言 | 脚本有效且默认值存在 | 通过 | pass |
| P0 engine 闭包 | 固定 SIG Go + Tailscale v1.82.5 + Linux OHOS SDK | AArch64 c-shared 且安全检查通过 | 28 MiB ELF64/AArch64；仅 `libc.so`；验证通过 | pass |
| llvm-readelf SIGPIPE 复现 | 六个动态符号的 `llvm-readelf | grep -q` | 捕获误导性错误 | 每次稳定输出 `write on a pipe with no reader` | red |
| engine 校验 SIGPIPE 回归 | 清理后的 `verify-engine.sh` | 校验通过且无 pipe error | 通过 | pass |
| HAP sibling 校验回归 | 清理外部 producer 的 `grep -q` 后运行 `pnpm run verify:hap` | 校验通过且无 pipe error | 通过 | pass |
| P1 静态检查 | 新增脚本、C ABI 头文件、Node-API SDK 签名 | 无 shell/C/C++ 诊断 | 通过 | pass |
| Go VCS stamping 回归 | 扫描 engine/smoke 两个构建入口 | 两者均显式关闭 stamping | 修复前 engine 首个失败；修复后均通过 | pass |
| P1 HAP 完整构建 | `pnpm run build:p1` | 构建并校验 HAP | 用户输出 `BUILD SUCCESSFUL`、`HAP verification passed` | pass |
| bridge RUNPATH 回归 | 检查 packaged bridge dynamic section | 不含 RPATH/RUNPATH | 修复前命中；修复后无 RPATH/RUNPATH 和 workspace 路径 | pass |
| P1 首次真机加载 | 调试签名 HAP / 设备 `5NC0226529000198` | 页面显示 Go smoke 通过 | 用户确认 `Go smoke: PASS` | pass |
| P1 100 次生命周期静态检查 | Go/C ABI/Node-API/ArkTS/build scripts | 编译接口与导出门禁一致 | 全部通过；待交叉编译和真机 | pass |
| P1 100 次生命周期真机 | 设备 `5NC0226529000198` | 100 对 start/stop 全部通过 | 用户确认页面 PASS | pass |
| P1 30 分钟门禁静态构建 | 定时 UI / start-stop N-API / 现有 smoke `.so` | ArkTS/C++/HAP 链路通过 | 签名 HAP 构建及校验通过；待重建 Go `.so` 后真机 | pass |
| P1 防熄屏与 tick 门禁静态检查 | Window API / C ABI / Node-API / shell scripts | API 22+ 可编译且符号一致 | SDK 接口确认；C/C++/shell 静态检查通过 | pass |
| P1 30 分钟真机持续运行 | 设备 `5NC0226529000198` / 保持前台亮屏 | 30 分钟且 Go tick 门槛通过 | 用户确认 `PASS (30m 0s)` | pass |
| P2 VPN 平台探针本地构建 | VPN Extension / protect / `/32` TUN / Native dup | ArkTS/C++ 无诊断且 HAP 声明完整 | signed HAP 构建成功；HAP/Clang/ShellCheck 通过 | pass |
| P2 VPN 启动路径真机 | Mate X7 / Start VPN probe | 独立 VPN 进程、protect、TUN dup、native 同进程均通过 | `READY protected=PASS tunDup=PASS sameProcess=PASS` | pass |
| P2 VPN 停止 fd 所有权真机 | Mate X7 / Stop VPN probe | 销毁原始 TUN 后复制 fd 仍有效，并显示 `dupOwnership=PASS` | `STOPPED dupOwnership=PASS sameProcess=PASS` | pass |
| P2 两阶段停止与可复制状态本地构建 | `pnpm run build:hap && pnpm run verify:hap` | ArkTS 编译、签名打包和 HAP 校验通过 | BUILD SUCCESSFUL；HAP verification passed | pass |
| P2 默认网络监听本地构建 | NetworkKit default network callback / GET_NETWORK_INFO | ArkTS 编译且权限进入 HAP | BUILD SUCCESSFUL；HAP verification passed | pass |
| P2 Wi-Fi/蜂窝切换真机 | Mate X7 / VPN READY 后切换默认网络 | `Network: SWITCH PASS WIFI->CELLULAR` 或反向 | `SWITCH PASS CELLULAR->WIFI netId=118 switches=2` | pass |

## 错误日志
| 时间戳 | 错误 | 尝试次数 | 解决方案 |
|--------|------|---------|---------|
| 2026-08-02 | zsh 一致性扫描的反引号导致 unmatched quote | 1 | 改用无反引号的固定模式 |
| 2026-08-02 | 自动启动 Rancher Desktop 被权限策略拒绝 | 1 | 不绕过，继续不依赖 Docker 的实施 |
| 2026-08-02 | diff check 退出码被误当 whitespace 错误 | 1 | 后续只读取 `--check` 输出 |
| 2026-08-02 | Hvigor 无权创建用户级缓存，提升权限也被拒绝 | 2 | 查找官方项目级缓存配置；否则等待用户手工构建 |
| 2026-08-02 | wrapper 下载固定 pnpm 时被沙箱网络拦截，提升请求被用户中止 | 1 | 使用当前 fnm pnpm 直接运行内置 Hvigor engine |
| 2026-08-02 | `pnpm exec` 在非 Node workspace 中拒绝运行，报 `NO_PACKAGE` | 1 | 不创建无关 `package.json`；直接使用同一 fnm 环境中的 Node 启动 Hvigor，依赖管理仍固定使用当前 pnpm |
| 2026-08-02 | 直启 Hvigor 时项目根目录缺少 `@ohos/hvigor-ohos-plugin` | 1 | 按 DevEco wrapper 的既有行为，将安装包内置 engine/plugin 链接到忽略的 `node_modules/@ohos` |
| 2026-08-02 | plugin 经真实路径加载后找不到 `@ohos/hvigor` | 1 | 将项目 `node_modules` 加入 `NODE_PATH`，依赖解析已通过 |
| 2026-08-02 | Hvigor 不接受 `DEVECO_SDK_HOME=.../sdk/default` | 1 | 核对 all-in-one SDK 根路径后重试 |
| 2026-08-02 | HAP 打包阶段找不到 Java Runtime | 1 | 使用 DevEco Studio 自带 JBR 设置 `JAVA_HOME` 后重试 |
| 2026-08-02 | Docker socket 被沙箱拒绝，提升检查也被策略拒绝 | 2 | 不再重试；保留为阶段 0 外部环境门禁 |
| 2026-08-02 | HDC 无法连接 server，未发现设备 | 1 | 不阻塞本地 P0 实现；P1/P2 真机验证前再检查 |
| 2026-08-02 | 固定 Tailscale 源码无法联网下载，提升也被策略拒绝 | 2 | 不再重试或绕过；只检查本机已有可信缓存 |
| 2026-08-02 | 第三次续跑仍无固定 Tailscale 源码、Linux SDK、Docker socket 或真机输入 | 3 | 阶段 0/P0 已达到外部输入阻塞条件，停止跨越硬门禁 |
| 2026-08-02 | 空白扫描包含 `entry/.cxx` 的 CMake 生成文件 | 1 | 修正多层构建目录忽略规则，再只扫描仓库源码 |
| 2026-08-02 | Tailscale 完整 clone 的 HTTP/2 stream 被取消，随后 `early EOF` | 1 | 固定 tag 浅克隆容器复验通过 |
| 2026-08-02 | SIG Go `cmd/dist` 构建时 Go runtime 在 `netpoll_epoll` SIGSEGV | 1 | 先运行最小 linux/amd64 Go 探针，区分仿真层与源码构建问题 |
| 2026-08-02 | `rdctl list-settings` 被本会话沙箱拒绝访问本地 daemon | 1 | 不绕过；请用户提供 VM type/Rosetta 设置或自行执行最小探针 |
| 2026-08-02 | 最小探针在拉取官方 Go 基础镜像时遇到 CloudFront EOF | 1 | 复用本地 `arkscale-p0:go1.24.5`，使探针离线运行 |
| 2026-08-02 | engine 的公开 Go modules 从 `proxy.golang.org` 下载时批量 TCP timeout | 1 | 用一个固定 module 测试 `goproxy.cn`，确认可达后再配置 P0 代理透传 |
| 2026-08-02 | `rg` 把以 `--env` 开头的固定搜索模式解析成命令选项 | 1 | 使用 `rg ... -- 'pattern'` 终止选项解析，断言通过 |
| 2026-08-02 | 复查旧模板时 `/Users/yangzhitao/repos/ArkWarden` 已不存在 | 1 | 不继续搜索外部工程；复用当前 CMake/Node-API 结构 |
| 2026-08-02 | macOS 宿主 Clang 直接读取 OHOS N-API 头缺少 musl `bits/alltypes.h` | 1 | 使用 DevEco OHOS Clang 的 AArch64 target/sysroot 重跑，源码通过 warnings-as-errors |
| 2026-08-02 | 自动执行 `pnpm run build:p1` 无权访问 Rancher Desktop Docker socket，受控提权也被策略拒绝 | 2 | 不绕过本地 daemon 权限；由用户终端运行同一条 P1 命令并回传输出 |
| 2026-08-02 | P1 Go build 报 `error obtaining VCS status: exit status 128` | 1 | 对本项目产物使用 `-buildvcs=false`；第三方源码版本仍在 build 前单独按 commit 校验 |
| 2026-08-02 | P1 bridge dynamic section 泄露宿主机绝对 RUNPATH | 1 | 先将检查写入 `verify:hap`，再从 CMake target 移除 build-tree rpath |
| 2026-08-02 | 自动执行 HDC 设备列表返回 `Connect server failed`，受控提权被拒绝 | 2 | 不绕过本机 daemon；由用户终端运行 `hdc list targets` |
| 2026-08-02 | 沙箱内执行 `hdc help` 仍等待本机 daemon | 1 | 不重复；使用本地文档和用户已确认的设备结果继续 |
| 2026-08-03 | P2 Stop 在 `onDestroy` 后未上报 `dupOwnership=PASS` | 1 | 改成 Extension 内先完成 destroy/dup 校验并发布 STOPPED，UI 再调用 stop ability |

## 当前诊断门禁
- P0 已完成；实现不含 Tailscale 的最小 Go c-shared library，并接入现有 Node-API/HAP。
- P0/P1/P2 已完成；当前进入 P3 Tailscale backend。
- P3 先审计 OpenHarmony 构建中误选的 Linux netns/netmon/router 路径，再接入 backend。

## 当前外部输入
- 无；下一步输入均在固定的 Tailscale v1.82.5 checkout 中。

## 五问重启检查
| 问题 | 答案 |
|------|------|
| 我在哪里？ | 阶段 P3：Tailscale backend |
| 我要去哪里？ | 先隔离错误选择的 Linux 平台路径，再接入 userspace engine 与 LocalBackend |
| 目标是什么？ | API 22+ ArkScale 最小客户端 |
| 我学到了什么？ | 见 `findings.md` |
| 我做了什么？ | 见上方记录 |
- P3 平台隔离审计已确认首批错误选择点：netns、netmon、router、magicsock 与 tstun。下一步产出一份 pinned Tailscale 可重放补丁，并将选中文件审计接入 P0 容器流水线。
- P3 隔离实现选型已收敛为调整 build constraint 并复用 Tailscale 现有 portable/default 文件；不新增一套平台实现。
- 错误记录：首次 `git apply --check` 报补丁第 68 行损坏；原因是手写 hunk 的行数与 `netns_default.go` 实际长度不一致。修正补丁 hunk 后再验证，不重复原命令。
- 已新增并成功应用 `0001-openharmony-platform-seams.patch`；连续运行两次 `fetch-deps.sh` 分别得到 `patch applied` 与 `patch already applied`，幂等性通过。
- 已新增 `audit-openharmony-platform.sh` 并接入 `p0-container.sh`；shell 语法检查通过。真实 `GOOS=openharmony` 文件选择仍需在 Linux 容器的下一次 `pnpm run build:p0` 中验证。
- 错误记录：尝试用 macOS 主机标准 Go 以 `GOOS=linux -tags=openharmony` 静态模拟选文件失败，主机 PATH 中没有 `go`（exit 127）。不安装额外 Go，也不重复；以已接入的 Linux 容器审计为准。
- P3 平台隔离节点的 shell 语法、根仓库/第三方补丁 whitespace、已应用补丁反向校验均通过；等待 Linux 容器完成真实选文件与 engine 重编译门禁。
- 错误记录：阶段提交前的 `git diff --cached --check` 将统一补丁文件中的 context 空行判为 trailing whitespace。改用等价的 zero-context (`--unified=0`) 补丁格式，既保持 `git apply` 可重放，也让仓库 whitespace 门禁有效。
- 错误记录：zero-context 补丁首次反向校验未带 `git apply --unidiff-zero`，Git 按默认安全策略拒绝无 context hunk。补丁应用与反向检查统一增加该明确选项。
- zero-context 补丁的反向检查、`fetch-deps.sh` 已应用识别、完整 staged whitespace 门禁均已通过；本地签名配置保持未暂存。
