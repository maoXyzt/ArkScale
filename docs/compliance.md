# 合规与安全交付

## 当前自动门禁

- `.env` 与签名材料默认忽略；`pnpm run check:secrets` 拒绝已暂存的环境文件、签名材料、Signing Config 密码、Tailscale auth/API/OAuth key、可复用登录 URL 和 PEM 私钥。
- P0 在 `build/compliance/` 生成 SPDX 2.3 SBOM 和实际依赖源码中的许可证、NOTICE 与 PATENTS 文本；模块版本、许可证登记或原文缺失时构建失败。
- ArkScale 源码采用 MIT 许可证；第三方组件继续适用各自许可证，不能按 ArkScale 的 MIT 许可证重新授权。
- Tailscale 状态位于应用私有目录，固定源码以 `0600` 原子写入；跨进程 mailbox 同样以 `0600` 创建。
- HAP 仅申请 `INTERNET` 与 `GET_NETWORK_INFO`，不申请系统级 `MANAGE_VPN`。
- `pnpm run verify:hap` 对 unsigned HAP 和本地存在的 signed HAP 执行相同的 ABI、API、权限与原生库检查，并拒绝产物中的 `MANAGE_VPN`。
- Tailscale backend 原始日志默认丢弃，异步健康事件只向页面发送固定消息；ArkScale 主动写入系统日志的 ArkTS 路径仅记录数字错误码。

页面的主动诊断会显示 peer 名称、Tailscale IP/DNS 名称、直连 endpoint、资源计数和探针错误。这些数据只用于本机排障，不会由 ArkScale 上传；复制诊断内容对外分享前应自行脱敏。登录 URL 和节点状态保存在应用私有目录或私有跨进程 mailbox，不写入系统日志。

## 尚未解除的交付阻塞

- 52 个 Go 运行时模块已按固定源码登记 SPDX 表达式；生成的原文包与登记仍需在发布前由人工或法律流程最终确认。
- 自部署前仍需由部署者完成隐私披露和签名密钥托管；ArkScale 不提供应用市场发行包，也不计划上架。

生成结果不入 Git；每个发布候选都必须从对应 commit 重新运行 P0，并随 HAP 一起归档 `build/compliance/`。
