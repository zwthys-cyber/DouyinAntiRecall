# 静态逆向依据

分析输入为用户提供的 抖音_Decrypted.zip。读取顶层 Payload/Aweme.app/Info.plist：

| 字段 | 值 |
| --- | --- |
| CFBundleIdentifier | com.ss.iphone.ugc.Aweme |
| CFBundleShortVersionString | 41.2.0 |
| CFBundleVersion | 412021 |
| MinimumOSVersion | 15.0 |

主可执行文件 Aweme 为启动壳，主要逻辑在 Frameworks/AwemeCore.framework/AwemeCore。该镜像为 thin arm64 Mach-O，LC_ENCRYPTION_INFO_64 的 cryptid 为 0。以下为静态镜像虚拟地址，无 ASLR slide；插件不使用硬编码地址。

| 类 / 方法 | 地址 | ObjC 类型编码 |
| --- | --- | --- |
| TIMXOMessage applyLogicWithModel_DouYin: | 0x15b7202c | v24@0:8@16 |
| TIMXOMessage applyLogicWithModel_Default: | 0x28110b70 | v24@0:8@16 |
| TIMXMessageORM recalled | 0x27f14df0 | B16@0:8 |
| TIMXMessageORM extDictionary | 0x14fb5520 | @16@0:8 |
| TIMXMessageORM setExtDictionary: | 0x157aae80 | v24@0:8@16 |
| TIMXMessageORM contentDictionary | 0x14f9c044 | @16@0:8 |
| TIMXMessageORM setContentDictionary: | 0x27f161b8 | v24@0:8@16 |
| TIMXNewMessageStore handleRecallMessageLocal:belogningConversationID:role:recallUserID:completion: | 0x280494a0 | v56@0:8@16@24q32@40@?48 |
| TIMXNewMessageStore userID | 0x14e37b88 | @16@0:8 |
| TIMXOModel db | 0x15b6da34 | @16@0:8 |

## 数据流证据

- `TIMXMessageORM.recalled` 调用 extDictionary，读取全局键 `s:is_recalled` 并调用 boolValue。
- `applyLogicWithModel_DouYin:` 在 0x15b7208c 起读取模型 extDictionary，写入消息的 syncedExtInternal。
- 0x15b7263c–0x15b72678 从同步扩展读取 `s:is_recalled` 并取 boolValue。
- 0x15b7269c–0x15b726ac 调用 setRecalled:YES。
- 后续调用 setRecalledContent: 保存撤回前内容，再把展示内容切换为空字典。
- 相邻全局键在 0x350c2c08、0x350c2c30、0x350c2c38 指向的 CFString 分别为 `s:is_recalled`、`s:recall_role`、`s:recall_uid`。
- 本地撤回写入路径在 0x28049c1c 起把 `s:is_recalled` 写为字符串 true。
- `TIMXNewMessageStore.userID` 通过 currentUserImp.currentAccountID 取得当前账号，再转为对象返回。

据此实现只 hook `applyLogicWithModel_DouYin:`：先检查当前账号和模型 sender，对他人撤回的模型做独立拷贝，去掉三个撤回字段，用之前观察到的 JSON 内容恢复模型内容，然后调用原方法一次。未获取到账号、原文或接口签名不符时，继续原逻辑。自己发送或当前账号执行的撤回直接转发。

## 范围

这是在展示模型转换处实现的本机保留方案，不阻止服务器撤回，也不修改抖音数据库。云端测试使用按观测 ABI 编写的模拟对象；尚无进程内调用轨迹、实际数据库变化或手机截图证据。因此该转换路径是否覆盖所有私信撤回场景、`db.userID` 在设备上的实际返回、消息拷贝实现和相关通知链均需真机验收。

不直接拦截全部 command/delete 方法：这些还处理会话删除、已读同步和其他业务，无法仅凭名称判断为撤回。未 hook 电商、直播或 Default 路径。

分析过程中只将目标文件作为数据读取，未执行抖音或插件；构建和测试由 GitHub Actions 完成。
