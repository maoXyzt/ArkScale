# ArkScale 侧载安装

ArkScale 不通过 AppGallery 分发。Release 提供的是由项目固定 commit 构建并校验过的 HAP；用户需要先使用自己的 HarmonyOS 签名材料签名，再安装到设备。

## 支持范围

- HarmonyOS NEXT compatible API 22 或更高；
- `arm64-v8a` 手机；
- 当前只有 HUAWEI Mate X7 完成端到端验证。

不符合这些条件的设备，即使安装成功也不代表受到支持。

## 安装步骤

1. 从 GitHub Release 下载 HAP 和 `SHA256SUMS`，在同一目录执行 `shasum -a 256 -c SHA256SUMS`（或 `sha256sum -c SHA256SUMS`）；HAP 文件名必须与 `SHA256SUMS` 中的条目完全一致。
2. 使用自己的证书和 Profile 对 HAP 签名。签名材料不要发送给项目方，也不要提交到仓库。
3. 安装设备命令行工具并开启开发者模式、USB 调试。
4. 下载 Release 附带的 `install-hap.sh`，然后执行：

   ```bash
   ./install-hap.sh /path/to/arkscale-signed.hap [connect-key]
   ```

   也可以使用已验证的图形化侧载工具完成同样的“签名 → 安装”流程。

5. 首次打开 ArkScale，接受系统 VPN 授权并完成 Tailscale 登录。

Release 中的 unsigned HAP 不能直接安装。调试签名可能绑定设备或有有效期；覆盖升级必须继续使用同一应用标识和兼容的签名身份。

## 维护者生成 Release 包

在完成 P1 构建和 HAP 校验后运行：

```bash
pnpm run package:release
```

脚本会生成 HAP、安装脚本、SHA-256、commit/设备范围清单，并在存在时附带 `build/compliance/`。它不会签名，也不会复制任何证书或密码。
