# 合规与安全交付

## 当前自动门禁

- `.env` 与签名材料默认忽略；`pnpm run check:secrets` 拒绝已暂存的环境文件、签名材料和 Signing Config 密码。
- P0 在 `build/compliance/` 生成 SPDX 2.3 SBOM 和实际依赖源码中的许可证文本；缺少许可证文件时构建失败。
- Tailscale 状态位于应用私有目录，固定源码以 `0600` 原子写入；跨进程 mailbox 同样以 `0600` 创建。
- HAP 仅申请 `INTERNET` 与 `GET_NETWORK_INFO`，不申请系统级 `MANAGE_VPN`。

## 尚未解除的交付阻塞

- 仓库根目录尚无项目许可证；在所有者选定许可证前，不应对 ArkScale 源码作开源授权声明。
- SPDX 中第三方模块的许可证结论保持 `NOASSERTION`；生成的原文包仍需在发布前由人工或法律流程确认。
- Release 日志策略、商业 HarmonyOS 分发政策、隐私披露和签名密钥托管仍待完成。

生成结果不入 Git；每个发布候选都必须从对应 commit 重新运行 P0，并随 HAP 一起归档 `build/compliance/`。
