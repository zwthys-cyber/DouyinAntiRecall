# 41.2.0 登录错误 2029 / 1049 静态追踪

2026-11-21。输入为用户提供的原始解密宿主；地址为该 AwemeCore 样本中的地址，仅适用于 41.2.0 / 412021。没有运行宿主、插件或登录请求，没有在服务器编译或执行目标测试。

## 设备证据与边界

v0.2.6 的设备报告显示宿主匹配、诊断观察点 4/4，账户错误处理方法先后收到 `toutiao.account.error.domain` 下的 2029 与 1049。没有“进入1049处理路径”事件。只能确认收到 NSError；报告不含原始响应，不能把每一条错误确定为服务器原样返回，也不能确定是哪一个签名字段导致。

## 1049 的明确语义

`TTAccountErrorCodeTask.initWithError:`，入口 `0x1451d5c4`：

- 从 NSError.code 取值，写入任务 errorCode。
- `0x1451d654` 比较 1049，命中后转到 `0x1451d754`。
- 该分支将任务类型设为 4，并取 `0x32e7b778` 指向的字符串常量。
- 该字符串为 `force_update`，CFString 位于 `0x352578b8`。

因此在这一宿主版本中，1049 有“强制升级任务”的明确静态映射。它不是单独证明证书、包标识、App Attest 或实际版本过旧的错误。

## 错误来源和显示路径

`TTAccountJSONResponseSerializer.normalParseResponseResult:resultError:exceptionInfo:exceptionAsError:originalURL:`，入口 `0x136a25ac`：

- 在 `0x136a29e4` 查询 `error_code`；在 `0x136a2a10` 通过整数读取方法取值。
- 同时存在 `message`、`data`、`error_description` 等响应解析路径。
- 这证明 SDK 支持把响应中的业务错误转成应用错误。现有设备诊断尚未记录解析前后的码，不能将本次调用路径当作已经动态证实。

`IESAccountErrorHandler.canHandleBySaaS:extraParams:response:completion:`，入口 `0x14513710`：

- `0x14513760` 比较 1049。
- 命中后调用 `canProcess1049Error`，条件满足时分发到 `process1049Error:fullData:completion:`。
- `canProcess1049Error`（`0x20430588`）检查 UI delegate 是否提供升级提示方法；该条件不是直接的签名验证。
- `process1049Error:fullData:completion:`（`0x20430654`）读取错误信息并调用 `accountsdkShowUpgradeAppAlertWithTitle:message:actions:`。默认标题/正文与设备截图一致。

还存在不同的升级入口：

- `IESAccountKMPRouterDependAdapter.openUpdateAppProcessContext:errorMsg:`，`0x20470020`，调用同一 UI delegate 升级提示方法。
- `openUpdateAppProcessV2Params:callback:`，`0x204701d4`，读取传入模型的 title / subtitle / confirmTitle / cancelTitle，转发 `showUpgradeAppAlertV2WithTitle:message:confirmTitle:cancelTitle:actionHandler:`。
- `IESAccountIdentityVerificationDecisionDispatcher.showForceUpdateDecision:completion:`，`0x20434418`，读取 decision 中 `operate_type=force_update` 及 copywriting。
- `IESAccountErrorHandler.handleError:extraParams:response:completion:`，`0x145294a0`，能经 `injectProcessMiddleCheck:completion:` 转入中间处理链。

所以“有 1049 却未进入旧 process1049Error”与存在多条处理链相容；尚不能确定本次具体走哪条。隐藏一个 UI 方法不是登录修复。

## 2029 尚未精确解释

在已追踪的账户任务构造与旧 SaaS 分发逻辑中，没有找到可直接命名为证书错误或 App Attest 错误的 2029 专用分支。任务构造对 2028 起的一段码使用范围和位掩码分类，不能只搜索立即数就断言没有处理。

不能把二进制里所有 2029 常量都视为登录错误，例如 `0x13676330` 的 2029 实际是网络磁盘缓存源码日志行号，紧邻 `Invalid table size`，与账户错误映射无关。

## 下一步隔离

当前签名身份与原始宿主的身份有差异，但“差异存在”与“它导致本次 1049”是两个命题，后者没有被证实。现阶段不建议仅据本报告改签名字段或重新全选权限。

准备同一原始解密 ZIP 的无插件对照包：与 v0.2.6 一样移除系统 PlugIns 扩展，但主程序保持原样，不添加 dylib 或加载命令。用设备上相同证书、相同签名设置对照登录：

- 相同错误：说明这个失败也可以在没有本插件时出现，优先继续追宿主版本、解密/重签和账户环境；仍不能锁定某个字段。
- 对照可以登录、插件包失败：继续查注入、插件初始化与只读诊断观察是否影响宿主。

对照包需要设备重新完整签名；文件打包不是安装或登录验证。仓库与公开 Release 不包含 IPA、描述文件、验证码、手机号或登录令牌。
