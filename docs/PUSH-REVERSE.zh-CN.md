# 41.2.0 推送绑定链静态核对

用户设备在 v0.2.7 中显示通知权限、横幅、声音、角标均开启，APNs 环境为 development，系统显示已注册，但真实后台私信仍无提醒。这只确认系统权限与注册标志，不确认宿主绑定或服务器投递。

只读取用户提供解密宿主的 Mach-O 元数据和指令，未在当前服务器运行宿主或插件。以下地址仅对应 41.2.0 / 412021。

| 环节 | 方法 | 地址 |
| --- | --- | --- |
| 系统成功回调 | `BDUGPushDelegateInjection.application:didRegisterForRemoteNotificationsWithDeviceToken:` | `0x6bcc070` |
| 系统失败回调 | `BDUGPushDelegateInjection.application:didFailToRegisterForRemoteNotificationsWithError:` | `0x6bccdfc` |
| 宿主请求令牌（类方法） | `BDUGPushService.requestDeviceToken` | `0x15154c94` |
| 宿主按需上传（类方法） | `BDUGPushService.uploadDeviceTokenIfNeeded` | `0x15413220` |
| SDK 处理令牌（类方法） | `BDUGPushManager.handleDeviceToken:` | `0x6bd4534` |
| 上传地址构造（类方法） | `BDUGPushManager.getUploadTokenURLWithRequest:` | `0x157017a0` |
| 宿主上传开始回调 | `AWEPushModule.bdug_pushDeviceTokenUploadStart:` | `0x115aa0b8` |
| 宿主上传结果回调 | `AWEPushModule.bdug_pushDeviceTokenUploadResult:` | `0x115aa160` |

`BDUGPushService.requestDeviceToken` 转发到通知中心服务的同名方法。`uploadDeviceTokenIfNeeded` 读取 SDK 持有的令牌，存在时交给 `handleDeviceToken:`。后者有 `isUploadDeviceToken:`、`disableUploadToken`、正在请求和频率控制，构造请求后再上传。地址构造包含 SDK 配置 host 下的 `/service/1/update_token/`；插件不自建该请求，不手动读取或拼接令牌。

v0.2.7 的本地修复只直接调用 UIApplication 的系统注册方法，没有显式发起宿主 SDK 按需绑定重试。v0.2.8 改为优先调用上述宿主类方法；接口类型或宿主版本不匹配时退回原系统注册。此处是补齐重试路径，不是证明原问题一定由缺少该调用引起。SDK 可能已自行上传过；按需调用也可能因其去重或限频而不再次上传。

新增四个只读观察点计数。成功/失败系统回调均保留原对象并调用原方法一次；上传回调只记录到达和次数，不查看其字典，因此不能把结果回调当作业务成功。注册失败只记录数字码，不保留错误正文；令牌、账号、请求和响应正文均不进入报告。计数从当前进程加载开始，0 不代表历史上从未上传。

`AWEPushModule.setServiceChannel`（`0x133ec6d4`）还会依据内部测试渠道设置调整 SDK channel。这不能等同于 `aps-environment`，目前没有动态证据确认环境或渠道不匹配是本次唯一原因。没有强改 channel、development/production 或签名字段；也没有关闭原限频、强制重置缓存或伪造上传成功。

设备验收：同一证书、包标识、移除 Embedded 设置覆盖插件，保持登录；进入消息通知修复，显式重试后数秒刷新并复制状态。观察系统成功/失败和宿主上传开始/结果的变化，最后由另一账号发私信验证后台实际提醒。云端模拟对象回归无法替代该真实投递结果。
