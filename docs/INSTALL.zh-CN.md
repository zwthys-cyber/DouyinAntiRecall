抖音防撤回插件安装说明（v0.2.0 实验版）

目标：抖音 41.2.0（412021），原始包标识 com.ss.iphone.ugc.Aweme；iOS 17.0。
版本或构建号不同会自动不启用，不能直接用于其他抖音版本。

1. 在 GitHub Releases 的 v0.2.0 页面下载 DouyinAntiRecall.dylib，或在 Actions 成功运行页面下载 ZIP 产物。
2. 解压，找到 DouyinAntiRecall.dylib。可用 SHA256SUMS 对照校验文件。
3. 在设备上用 TrollStore 安装自己已有的 41.2.0 解密安装包。
   原始 ZIP 若顶层为 Payload，可保留 ZIP 原件，复制一份改名 .ipa 后交给 TrollStore。
   本仓库不提供或上传抖音安装包。
4. 完全退出抖音。在 TrollFools 选择这个抖音，导入 DouyinAntiRecall.dylib 并完成注入。
5. 重新打开抖音，用另一个账号发送文字消息；先让接收端收到并打开聊天，随后在发送端撤回。
6. 对方撤回后，消息气泡下方或右侧应出现小号灰色“已撤回”。消息原文不追加提示，普通消息不显示标签。
7. 保持聊天页面打开，让对方撤回。标签应直接出现，无需返回主页。再检查重启后状态及自己发送的消息是否仍可撤回。

从旧版升级：先完全退出抖音，在 TrollFools 移除旧的 DouyinAntiRecall.dylib，再导入新版本并重启抖音。不要同时注入两个版本。缓存可以保留。
已保留且上游撤回标记仍在的旧消息，重新进入聊天加载时也会应用新标签。

这是动态库，需要注入应用才能加载；只在文件管理器打开 dylib 不会启用。
插件不带设置界面，成功加载且版本吻合后自动生效。

移除：退出抖音，在 TrollFools 中移除此动态库，重新打开抖音。
如果出现启动异常，先在 TrollFools 移除注入，再恢复使用。

缓存目录：抖音沙盒 Library/Application Support/DouyinAntiRecall/
有沙盒访问权限时，可在停止抖音后删除该目录清除插件消息缓存。
移除动态库不会自动清除缓存。

安装方式参考：
https://github.com/Lessica/TrollFools/blob/main/README.md
https://github.com/opa334/TrollStore

云端编译和模拟测试不能替代抖音真机验收。

新版入口：抖音自己的“设置”页面顶部 → 抖音增强。新增属地、音频、原图功能默认关闭，请按需启用；设置页可直接打开音频库。完整操作见 docs/FEATURES.zh-CN.md。
