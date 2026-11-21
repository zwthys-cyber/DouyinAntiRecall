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

## v0.1.1 撤回状态提示

检测到他人撤回并成功保留原内容后，若内容字典的 text 字段为非空 NSString，在其副本末尾附加 `\n【对方已撤回】`。只修改传给原转换方法的副本；缓存仍保持原文，原始 ORM 数据不变。用后缀检查避免重复标识，末尾追加可保留原有文字中的提及偏移。非文字内容保持原数据结构。该新增展示方式仍需真机确认。

## v0.1.2 独立灰色标签

移除 v0.1.1 的文字后缀；只在副本扩展中加入插件字段 `dar_retained_recall_v2=1`。通过 AWEIMMessage.syncedExt 读取展示状态，正文和原文缓存保持不变。

UI 接口静态依据：AWEIMMessageBaseTableViewCell.layoutSubviews (0x22034c5c)、configWithMessage: (0x2203556c)、message (0x220365dc)、viewModel (0x220365f8)、visibleContentView (0x22035a60)、containerView (0x22035ef4)。visibleContentView 为基类接口，实际视图由子类提供；无有效气泡视图时不显示标签。

在布局完成后将一个 UILabel 放入单元格 contentView，字号 10，系统 secondaryLabelColor。优先使用气泡下方空位，次选右侧；空间不足时隐藏，避免覆盖文字或相邻单元格。prepareForReuse 和 configWithMessage: 会立即隐藏旧标签。没有修改行高，不写入服务器或应用的原模型。

模拟器测试使用已观察接口的模拟聊天单元格验证 UIKit 布局及复用，不代表已经覆盖抖音所有实际单元格子类；新增标签需要真机验收。

组件化聊天单元格补充接口：AWEIMReusableCommonCell.renderWithHolder: (0x21ba6e58)、prepareForReuse (0x21ba6d94)、currentContext (0x21ba7194)，上下文 AWEIMMessageComponentContext.message (0x22058028)、messageViewModel (0x22057f20)。读取上下文消息状态，在已定位的 AWEIMMessageBubbleThemeView / GradientView / AnimationBubbleView 视图族旁放置标签。仅对成功保留的消息查找视图，遍历上限 256 个视图。

## v0.1.3 可见单元格主动刷新

v0.1.2 仅在布局及配置时读取显示标记。收到撤回后，SDK 消息已经更新，但可见单元格可能仍持有旧 AWEIMMessage 副本，而且未发生新的布局，因此出现“返回主页再进入才显示”的现象。

成功保留消息后，在原 SDK 方法完成之后发出主线程通知，携带账号/会话/消息标识。通过弱引用追踪配置过的聊天单元格，匹配其 SDK 身份后直接更新标签，并安排后续布局。AWEIMMessage 使用已观察的 transToIESMessage 接口解析身份；不改写旧展示副本内容。即时状态与完整身份绑定，prepareForReuse 清除，其他账号/会话/消息不会套用。

通知接收端有重入保护，避免桥接身份 getter 触发 SDK 转换时递归刷新；未知对象或异常只影响该单元格的标签刷新，不重跑原 SDK 方法。

## v0.2.0 功能接口

参考仓库 ac54u-mobile/Aweme，固定提交 a7138914a7de63bfc6964e622723d2fc75cbb2cc；仅移植请求的功能及离线城市映射。许可证见 THIRD_PARTY.md。

41.2.0 静态元数据对应：AWESettingsViewModel.sectionDataArray (0x1d7bc6bc)，AWESettingItemModel.setCellTappedBlock: (0x1d7ec8a4)，AWEPlayInteractionTimestampElement.timestampLabel (0x18cc7ffc)，两个长按面板 dataArray (0x173bddd8 / 0x173e9384)，AWEImageAlbumImageModel.watermarkFreeUrlList (0x146ccdf8)。

评论音频入口：AWECommentAudioRecorderController.audioRecorderDidFinishRecording:success:error: (0xfea0b08)、AWECommentAudioUploadManager.startUploadAudioWithFilePath: (0xfea9220)、_TtC31AWECommentMediaManagerSwiftImpl27CommentMediaUploaderManager.audioUploader: (0x67c53c)。旧录音完成回调读取 recorder.url.path 和 currentTime，替换文件后在调用原回调前同步录音时长；上传器处理仅作用于下一条已明确准备的评论音频。

Swift 上传入口只处理通过 ObjC getter 提供 audioFilePath/filePath/fileURL 的输入或已知包装字段；没有修改 Swift 本机调用约定或猜测对象内存布局。无法解析的载荷走原方法，后续仍可由评论专用上传路径处理。新增功能需真机确认各实际路径是否被覆盖。
