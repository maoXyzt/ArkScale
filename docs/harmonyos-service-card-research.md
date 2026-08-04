# HarmonyOS 服务卡片可行性核对

> 核对日期：2026-08-05
>
> 适用基线：HarmonyOS NEXT compatible API 22、target API 24，Stage 模型，phone。

## 1. 结论

ArkScale 可以增加 HarmonyOS 服务卡片，且当前项目是普通 HarmonyOS 应用并不构成限制：Form Kit 明确支持“应用”和“原子化服务”作为卡片提供方。当前 API 22/24 基线也足够，`FormExtensionAbility` 和 `formProvider` 从 API 9 起可用，ArkTS 卡片是官方推荐方案。[Form Kit 简介](https://gitee.com/openharmony/docs/blob/master/zh-cn/application-dev/form/formkit-overview.md) [FormExtensionAbility API](https://gitee.com/openharmony/docs/blob/master/zh-cn/application-dev/reference/apis-form-kit/js-apis-app-form-formExtensionAbility.md)

建议首版只做 **2×2 状态卡片**：展示“已连接 / 未连接 / 需要登录”和简要节点信息，点击卡片用 `router` 拉起 ArkScale 前台完成登录或 VPN 启停。不要让卡片直接启停 `VpnExtensionAbility`。

## 2. 名词和应用形态

- Form Kit 的正式能力名是“服务卡片”，文档也简称“卡片”；OpenHarmony 文档中的“原子化服务”对应产品语境中的元服务。
- 普通应用和原子化服务都可以提供卡片，因此 ArkScale 无需把当前 `installationFree: false` 的普通应用改造成元服务。
- Form API 从 API 11 起标注支持原子化服务，但当前 SDK 的 VPN API 没有原子化服务标记；ArkScale 应继续保持普通应用形态。
- 卡片提供方是应用；桌面是卡片使用方；卡片管理服务负责生命周期和事件转发。普通应用不能作为卡片宿主，这与 ArkScale 只向系统桌面提供卡片无冲突。[Form Kit 简介](https://gitee.com/openharmony/docs/blob/master/zh-cn/application-dev/form/formkit-overview.md)

## 3. 最小工程改动

使用与应用共 HAP 的动态 ArkTS 卡片即可，不需要新增独立模块。独立卡片包虽从 API 20 起支持，但会增加模块关联和版本一致性要求，对自部署项目没有收益。[创建 ArkTS 卡片](https://gitee.com/openharmony/docs/blob/master/zh-cn/application-dev/form/arkts-ui-widget-creation.md)

需要新增：

1. `entry/src/main/ets/formextension/ArkScaleFormExtension.ets`
   - 继承 `FormExtensionAbility`；
   - 至少实现 `onAddForm`、`onUpdateForm`、`onFormEvent`、`onRemoveForm`；
   - 通过 `formBindingData` 提供状态，通过 `formProvider.updateForm()` 更新卡片。
2. `entry/src/main/ets/widget/pages/ArkScaleCard.ets`
   - ArkTS 卡片 UI；
   - 使用 `@LocalStorageProp` 接收提供方数据；
   - 点击时使用 `postCardAction({ action: 'router', abilityName: 'EntryAbility' })` 打开应用。
3. `entry/src/main/resources/base/profile/form_config.json`
   - 声明 `src`、`uiSyntax: "arkts"`、`isDynamic`、尺寸、刷新策略和设备类型。
4. `entry/src/main/module.json5`
   - 在 `extensionAbilities` 中增加 `type: "form"`；
   - `metadata.name` 固定为 `ohos.extension.form`，`resource` 指向 `$profile:form_config`。

官方配置结构和字段见[配置 ArkTS 卡片的配置文件](https://gitee.com/openharmony/docs/blob/master/zh-cn/application-dev/form/arkts-ui-widget-configuration.md)，生命周期示例见[管理 ArkTS 卡片生命周期](https://gitee.com/openharmony/docs/blob/master/zh-cn/application-dev/form/arkts-ui-widget-lifecycle.md)。

## 4. 运行和状态同步限制

ArkTS 卡片 UI 运行在系统卡片渲染服务中，不在 ArkScale 主进程或 VPN 进程内；`FormExtensionAbility` 也有独立进程。各进程内存隔离，但应用侧进程共享文件沙箱。[ArkTS 卡片进程模型](https://gitee.com/openharmony/docs/blob/master/zh-cn/application-dev/form/arkts-ui-widget-process.md)

因此卡片不能直接读取当前 `Index.ets` 的 `@State`，也不应持有 VPN 引擎。最小可靠方案是保存一份非敏感的“最后已知状态”快照，卡片创建或刷新时读取；VPN 状态变化后由应用提供方调用 `formProvider.updateForm()` 主动刷新已添加的卡片。不要把认证密钥、登录 URL 或完整诊断日志放进卡片数据。

`FormExtensionAbility` 不能常驻后台：生命周期回调结束后最多再存活约 10 秒，长任务必须交给主应用处理。因此不能把 Tailscale backend、探测或持续监听放到卡片扩展中。[管理 ArkTS 卡片生命周期](https://gitee.com/openharmony/docs/blob/master/zh-cn/application-dev/form/arkts-ui-widget-lifecycle.md)

## 5. 刷新约束

- 提供方可通过 `formProvider.updateForm()` 主动更新自己的卡片；卡片按钮也可用 `message` 触发 `onFormEvent` 后更新。[ArkTS 卡片主动刷新](https://gitee.com/openharmony/docs/blob/master/zh-cn/application-dev/form/arkts-ui-widget-active-refresh.md)
- `updateDuration` 单位为 30 分钟，正整数 `N` 表示每 `30×N` 分钟刷新；与 `scheduledUpdateTime` 同时配置时，`updateDuration` 优先。[卡片配置字段](https://gitee.com/openharmony/docs/blob/master/zh-cn/application-dev/form/arkts-ui-widget-configuration.md#%E9%85%8D%E7%BD%AE%E6%96%87%E4%BB%B6%E5%AD%97%E6%AE%B5%E8%AF%B4%E6%98%8E)
- `setFormNextRefreshTime()` 的最短间隔为 5 分钟；每张卡片每天最多触发 50 次定时类刷新；第一次定时刷新最多可能有 30 分钟偏差；卡片不可见时布局刷新会延后到再次可见。[ArkTS 卡片被动刷新](https://gitee.com/openharmony/docs/blob/master/zh-cn/application-dev/form/arkts-ui-widget-passive-refresh.md)
- API 22 支持从 UIAbility 用 `reloadForms` / `reloadAllForms` 批量请求刷新，但首版只有一种卡片，无需使用批量接口。[ArkTS 卡片主动刷新](https://gitee.com/openharmony/docs/blob/master/zh-cn/application-dev/form/arkts-ui-widget-active-refresh.md)

对 ArkScale，连接状态变化应走主动刷新；周期刷新只作为低频兜底，建议 `updateDuration: 0`，避免无意义唤醒。

## 6. 点击动作和 VPN 启停

卡片正式支持的交互只有三类：

- `router`：将当前应用的 `UIAbility` 拉到前台；
- `call`：将当前应用的 `UIAbility` 拉到后台并调用已注册方法；
- `message`：拉起 `FormExtensionAbility` 并回调 `onFormEvent`。

这些动作没有直接指向 `VpnExtensionAbility` 的类型。[ArkTS 卡片页面交互概述](https://gitee.com/openharmony/docs/blob/master/zh-cn/application-dev/form/arkts-ui-widget-event-overview.md)

此外，卡片 UI 只能导入明确标注“支持在 ArkTS 卡片中使用”的模块，不支持 native 代码，也不支持加载 native so。因此 `ArkScaleCard.ets` 不能直接导入 Network Kit、调用 `vpnExtension.startVpnExtensionAbility()`，也不能调用 ArkScale Node-API/Go bridge。[ArkTS 卡片概述](https://gitee.com/openharmony/docs/blob/master/zh-cn/application-dev/form/arkts-form-overview.md#%E7%BA%A6%E6%9D%9F%E4%B8%8E%E9%99%90%E5%88%B6)

也不应在 `message` 触发的 `FormExtensionAbility.onFormEvent()` 中间接启动 VPN：FormExtension 约 10 秒无回调即退出，而 VPN 官方规定调用 `startVpnExtensionAbility()` 的应用进程退出时会主动停止 VPN，无法形成稳定连接。

技术上可用 `call` 先拉起一个后台 `UIAbility`，再由该 Ability 转调 VPN API；但官方要求 `call` 场景额外声明 `ohos.permission.KEEP_BACKGROUND_RUNNING`，且 VPN 首次连接必须弹出用户信任授权，官方还要求 VPN 应用提供可见的手动启停控件。VPN 调用方进程退出时，系统会主动停止 VPN。[call 事件](https://gitee.com/openharmony/docs/blob/master/zh-cn/application-dev/form/arkts-ui-widget-event-call.md) [连接 VPN](https://gitee.com/openharmony/docs/blob/master/zh-cn/application-dev/network/net-vpnExtension.md)

所以首版结论是：

- **支持**：卡片展示状态，点击后用 `router` 打开 ArkScale；
- **不直接支持**：卡片 UI 直接调用 VPN 或 Go 引擎；
- **暂不采用**：`call` 后台中转启停 VPN。只有用户明确需要“一键断开”且完成目标真机授权、进程存活和异常恢复 PoC 后再评估。

## 7. 权限、签名和设备

- 基础卡片提供方没有额外的 Form 权限要求；配置 `FormExtensionAbility` 和 `form_config.json` 即可。卡片若自行访问网络，需要 `ohos.permission.INTERNET`，ArkScale 已声明该权限。
- 只有采用 `call` 拉起后台 UIAbility 时才需要额外声明 `ohos.permission.KEEP_BACKGROUND_RUNNING`；该权限是 `normal`、`system_grant`，无需运行时授权弹窗。推荐的 `router` 方案不需要它。[call 事件](https://gitee.com/openharmony/docs/blob/master/zh-cn/application-dev/form/arkts-ui-widget-event-call.md) [权限定义](https://gitee.com/openharmony/security_access_token/blob/master/services/accesstokenmanager/permission_definitions.json)
- “卡片使用方/宿主”能力仅系统应用开放并需要系统签名；ArkScale 是卡片提供方，不需要系统签名。[卡片使用方开发指导](https://gitee.com/openharmony/docs/blob/master/zh-cn/application-dev/form/widget-host-development-guide-sys.md)
- 真机安装仍必须使用证书和 Profile 对 HAP 签名，这与是否包含卡片无关；自部署调试包无需因此上架应用市场。[HarmonyOS 开发入门：签名](https://developer.huawei.com/consumer/cn/develop-novice-guide/)
- Form Kit 支持手机、平板、PC/2in1、智慧屏、手表和车机，不支持轻量级智能穿戴。当前模块只声明 `deviceTypes: ["phone"]`，首版卡片也应显式设置 `supportDeviceTypes: ["phone"]`；该字段从 API 22 起支持，正好符合项目 compatible API。[Form Kit 简介](https://gitee.com/openharmony/docs/blob/master/zh-cn/application-dev/form/formkit-overview.md) [卡片配置字段](https://gitee.com/openharmony/docs/blob/master/zh-cn/application-dev/form/arkts-ui-widget-configuration.md#supportdevicetypes%E6%A0%87%E7%AD%BE)

## 8. 推荐验收

1. 签名 HAP 安装后，桌面长按 ArkScale 图标可进入卡片管理并添加 2×2 卡片。
2. 未登录、已停止、连接中、已连接、错误五种状态显示正确，且不暴露敏感数据。
3. 点击卡片只打开 ArkScale；首次 VPN 授权、登录和启停仍在应用前台完成。
4. 应用启动、停止 VPN、网络切换和进程重启后，卡片最终状态与应用一致。
5. 卡片不可见、桌面重启、应用覆盖安装后不会启动常驻探测或重复 VPN 实例。
