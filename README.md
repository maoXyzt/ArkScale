# ArkScale

ArkScale 是面向 HarmonyOS NEXT 的实验性 Tailscale 全设备 VPN 客户端。

它让 HarmonyOS NEXT 手机加入现有 tailnet，并通过 Tailscale 访问其他设备。项目仅供学习、研究和自部署，目前不提供应用市场版本或官方预编译 HAP；使用者需要自行构建、签名并安装。

> 当前状态：最小客户端已在一台 HarmonyOS NEXT 真机通过端到端验证，但 24 小时长稳、低内存恢复和更多机型兼容性仍待验证，不应视为完整或生产级支持。

## 能做什么

- 通过系统 VPN 授权连接和断开 Tailscale；
- 完成交互式登录，保存身份并在重启后恢复；
- 查看 tailnet 中的其他设备及其在线状态；
- 访问 peer 的 Tailscale IPv4、IPv6 和 MagicDNS 名称；
- 使用 DERP 中继或公网 UDP 直连；
- 在 Wi-Fi、蜂窝网络和飞行模式切换后恢复连接；
- 提供 TSMP、MagicDNS、TCP 和连接路径诊断；
- 退出登录并删除本机保存的 Tailscale 身份。

暂不支持 Taildrop、出口节点、发布子网路由、按应用分流和应用市场分发。

## 兼容性

| 项目 | 当前范围 |
| --- | --- |
| 系统 | HarmonyOS NEXT，compatible SDK API 22+ |
| 设备 | arm64 手机 |
| 已验证 | HUAWEI Mate X7，HarmonyOS `7.0.0.100(SP10C00E32R4P4)` |
| 网络能力 | Tailscale IPv4/IPv6、MagicDNS、DERP、UDP 直连 |

目前只验证过上述一款设备。其他 API 22+ 设备可能可用，但需要重新验证 VPN 行为、Go 运行时和后台限制。完整结果见[设备验证矩阵](docs/device-matrix.md)。

## 获取与安装

[GitHub Releases](https://github.com/maoXyzt/ArkScale/releases) 当前用于标记源码版本，不包含可直接安装的 HAP。自行安装需要：

1. 获取源码；
2. 使用 DevEco Studio 6.1.1 配置本机调试或发布签名；
3. 按[开发者指南](docs/development.md)构建并校验 HAP；
4. 将签名后的 HAP 安装到已连接的 HarmonyOS NEXT 设备。

签名文件、密码和其他凭据不要提交到仓库。

## 使用

首次打开 ArkScale 后，点击“连接”：

1. 接受系统 VPN 授权；
2. 在浏览器中完成 Tailscale 登录；
3. 返回 ArkScale，等待状态变为“已连接”。

“其他设备”会显示当前 tailnet 中的 peer，在线设备排在前面。可以选择设备运行 TSMP 测试；“诊断工具”还可验证 MagicDNS、TCP 连接和当前使用的直连或 DERP 路径。

“断开连接”只停止 VPN，不删除登录身份。若要让这台手机退出 tailnet，请使用“退出并删除身份”；下次连接时需要重新登录。

## 已知限制

- 尚未完成 24 小时连接和低内存恢复验证；
- 尚未覆盖登录取消、凭据吊销和控制面长时间不可达等场景；
- 其他手机型号和系统补丁版本未经验证；
- 首页最多显示 50 个 peer，暂时没有面向大型 tailnet 的分页设备页；
- 项目不提供应用市场包、签名服务或商用支持。

## 隐私与安全

Tailscale 状态保存在应用私有目录，ArkScale 不上传诊断数据，backend 原始日志默认丢弃。

诊断页面可能显示 peer 名称、Tailscale IP、DNS 名称和直连 endpoint。复制或分享诊断信息前请自行脱敏。不要公开登录 URL、auth key、OAuth secret、节点私钥或签名材料。

## 开发文档

- [开发者指南](docs/development.md)：环境、构建、架构、固定依赖和验收流程；
- [实施设计](docs/design.md)：C ABI、生命周期、平台适配和 P0–P5 设计；
- [设备验证矩阵](docs/device-matrix.md)：已验证设备、通过项和未覆盖项；
- [事实核对与实现研究](docs/implementation-research.md)：一手资料与技术路线证据；
- [合规与安全交付](docs/compliance.md)：secret 检查、SBOM、许可证和交付边界；
- [HarmonyOS 服务卡片研究](docs/harmonyos-service-card-research.md)：服务卡片能力和限制。

## 许可证

ArkScale 源码采用 [MIT License](LICENSE)。第三方组件适用各自许可证；自部署和再分发前请查看构建生成的第三方许可证包。
