# 设备验证矩阵

## 支持基线

- 设备类型：phone
- ABI：arm64-v8a
- compatible SDK：API 22
- compile SDK：API 24

## 已验证设备

| 设备 | 系统构建 | 验证范围 | 结果 |
| --- | --- | --- | --- |
| HUAWEI Mate X7（DEL-AL20） | HarmonyOS `7.0.0.100(SP10C00E32R4P4)` | Go c-shared 加载、100 次 smoke 启停、30 分钟 soak | PASS |
| 同上 | 同上 | 独立 VPN 进程、process protect、TUN FD 所有权、动态配置重建 | PASS |
| 同上 | 同上 | DERP/直连、MagicDNS、IPv4/IPv6 peer TCP、Wi-Fi/蜂窝切换 | PASS |
| 同上 | 同上 | UI 任务重建、强制停止、飞行模式、设备重启恢复 | PASS |
| 同上 | 同上 | 30 秒资源回归：FD `47→46`、RSS `+204 KB` | PASS |
| 同上 | 同上 | 5 轮连续 VPN/backend 完整启停；每轮启动和 TUN FD 回收门禁 | PASS |

设备序列号、tailnet 标识、公网 endpoint 和签名信息不进入矩阵。

## 未覆盖

- 其他 API 22+ 手机型号和系统补丁版本；
- 24 小时连接、低内存回收和长期后台限制；
- 登录取消、凭据吊销、控制面长时间不可达；
- release 签名、升级安装和商业分发流程。

新设备只有完成 P1–P4 功能门禁、短时资源回归和异常恢复后，才能加入“已验证设备”。
