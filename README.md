# DouyinAntiRecall

抖音 **41.2.0 / 412021** 的实验性本地消息防撤回插件，目标环境为 **iOS 17.0 + TrollStore + TrollFools**。

产物为独立 `DouyinAntiRecall.dylib`，不依赖 Substrate 或越狱插件加载器。通过 Objective-C runtime 替换已确认的消息转换方法，在他人撤回消息时保留本机已接收内容。自己发出的消息，以及当前账号执行的群消息撤回，继续走原逻辑。

**状态：GitHub Actions 已通过 iOS arm64 编译、签名和模拟回归测试，尚未完成抖音真机验证。** 云端测试通过不能证明抖音所有聊天场景均已生效。当前实现覆盖 `TIMXOMessage.applyLogicWithModel_DouYin:` 转换路径；其他 SDK、直播、电商客服、群管理员撤回及离线同步路径是否覆盖，需真机确认。

- [安装及移除](docs/INSTALL.zh-CN.md)
- [逆向依据和边界](docs/ANALYSIS.zh-CN.md)
- [验证范围及手机验收步骤](docs/VALIDATION.zh-CN.md)

## 下载

可直接在 [v0.1.0 预发布页面](https://github.com/zwthys-cyber/DouyinAntiRecall/releases/tag/v0.1.0) 下载 `DouyinAntiRecall.dylib`。

[已通过的云端构建和模拟测试](https://github.com/zwthys-cyber/DouyinAntiRecall/actions/runs/44854915146/attempts/2)，对应源码提交 `fca0e88`。也可进入 **Actions → Build and validate → 成功运行 → Artifacts → DouyinAntiRecall-41.2.0-arm64** 下载 ZIP 产物。

工作流在 macOS runner 中先编译运行模拟消息测试，再交叉编译 iOS arm64 动态库并检查签名和依赖。推送 main 或手动 workflow_dispatch 均可触发。不上传或运行抖音应用，不需要私有 SDK、Theos 或第三方 hook 框架。

## 本地缓存

已观察到的他人消息 JSON 内容保存在抖音自己的沙盒：

`Library/Application Support/DouyinAntiRecall/messages.json`

按当前账号、会话、消息标识分隔；最多 1000 条、内容总计约 8 MiB、单条不超过 64 KiB。写入有约 2 秒延迟。缓存不会上传，目录排除 iCloud 备份，iOS 文件使用首次解锁后的数据保护。消息内容以 JSON 存在本机，不额外加密。卸载插件不会自动删除缓存；可在停止抖音后用具备沙盒访问能力的工具删除该目录。设备强制结束进程可能丢失最近未刷盘内容。

不能凭空恢复未收到的消息，也不能保证恢复已被服务器删除的图片、视频、语音附件。插件不会阻止服务器撤回，也不会让其他设备恢复显示。若插件未观察到原文且更新模型中也无原文，会保留原应用的撤回状态。

## 开发

- `src/DouyinAntiRecall.m`：版本检查、ABI 检查、接收消息转换 hook。
- `src/DARCache.m`：有界本机 JSON 缓存。
- `tests/MessageHookTests.m`：GitHub macOS runner 使用模拟消息对象测试实际 hook 源码。
- `tools/objc_dump.py`：只读取 Mach-O 的静态 ObjC 元数据提取脚本，不加载目标二进制。
- `.github/workflows/build.yml`：云端测试和构建。

仓库只包含原创插件代码和必要的接口分析摘要，不包含抖音 IPA、AwemeCore、聊天记录或用户凭据。
