# 给你的蓝色绣球花

一个面向 Android 的私人陪伴应用，也是一份可以长期保存的数字礼物。项目以 Flutter 构建主要界面，以 Kotlin 接入 Android 原生能力，并通过 DeepSeek API 提供临时的陪伴文字与情绪沟通辅助。

应用采用“**本地长期记录 + 用户主动触发的临时 AI 请求**”架构：回忆、心情、纪念日和专注历史保存在当前设备；只有在用户主动使用“今日花语”或“情绪解语”时，本次填写及主动选择的文字才会经 HTTPS 发送给 DeepSeek。项目不提供账号系统、业务服务器、云同步或双设备自动共享。

## AI 核心能力

### 今日花语

- 以内联折叠面板呈现在花园首页，不跳转独立页面。
- 用户可以输入一句当下感受，或主动引用当天的一条心情记录。
- 根据所选语气生成简短、克制且具有陪伴感的文字。
- 输入、引用内容和生成结果仅保留在当前运行内存中，收起面板后清空，不写入 SQLite。

### 情绪解语

- 在“心语”主标签内完成情绪描述、事件补充、真实诉求梳理和沟通表达组织。
- DeepSeek 返回结构化分析，包括情绪理解、需要澄清的问题、沟通建议及可直接参考的表达示例。
- 支持根据补充信息继续整理，也可以通过用户反馈重新调整分析结果。
- 页面不会自动读取照片、回忆、纪念日或完整心情数据库，只处理用户本次主动提交的内容。
- 功能用于辅助梳理和表达，不进行心理诊断，不替代专业心理咨询、医疗服务或紧急援助。

### AI 调用与安全设计

- 通过 DeepSeek Chat Completions API 完成生成请求，并使用结构化 JSON 约束模型输出。
- 对返回内容执行字段、类型和长度校验，避免异常响应直接进入界面。
- 实现连接超时、响应超时、内容大小限制、任务取消和请求版本校验，防止迟到响应覆盖新结果。
- 两项 AI 功能共用一份用户自行配置的 API Key；密钥不会写入源码或 SQLite。
- API Key 由 Kotlin 原生模块通过 Android Keystore 生成的 AES-GCM 密钥加密，并以 AtomicFile 方式写入应用的非备份私有目录。

> AI 内容可能存在偏差。请勿将 DeepSeek API Key、签名文件、密码或真实私人数据提交到公开仓库。

## 主要功能

- **花园首页：** 每日问候、本地随机短句、纪念日入口、今日花语、白噪音和横屏专注时钟入口。
- **我视角下的他：** 记录日期、标题、文字与本地照片，支持新增、修改、删除及日期筛选。
- **心语／情绪解语：** 在当前页面完成 AI 情绪梳理、补充提问、沟通建议、表达改写和反馈修订。
- **我们的回忆：** 每条回忆最多保存 20 张照片，支持相册与相机导入、封面排序、详情展开、编辑、删除及日期筛选。
- **今日心情：** 记录开心、普通、有点累和不开心四类心情，支持备注、编辑、删除、日期筛选以及周／月图表统计。
- **纪念日：** 最多保存 100 条重要日期，展示已经过去或仍需等待的天数，并在周年当天提供首页提醒。
- **白噪音：** 内置三段约 50 分钟的真实音频资源，通过单独播放或混合形成六种音色，并使用双播放器交叉淡化降低循环接缝。
- **横屏专注时钟：** 包含实时时钟、正计时、倒计时和 25/5 番茄钟，支持全屏专注、后台计时、系统通知、分类记录、日期筛选和趋势统计。
- **本地保存：** SQLite v8 使用 7 张数据表管理长期资料，照片复制到 App 私有目录；卸载应用会清除这些本地数据。

## 技术架构

```text
Flutter 页面与动画
├─ 本地业务层
│  ├─ SQLite：回忆、心情、纪念日、视角记录、专注历史和设置
│  ├─ App 私有目录：回忆照片
│  └─ Assets：随机短句与白噪音资源
├─ AI 生成层
│  ├─ 今日花语：临时陪伴文字
│  ├─ 情绪解语：结构化情绪与沟通辅助
│  └─ HTTPS：DeepSeek Chat Completions API
└─ Android 原生层
   ├─ 后台计时、前台服务与通知交互
   ├─ 音频提醒与屏幕状态适配
   └─ Android Keystore、AES-GCM 与 AtomicFile 凭据保护
```

## 项目结构

```text
assets/
├─ data/                         本地随机短句
└─ audio/                        50 分钟白噪音资源
lib/
├─ features/
│  ├─ ai/                        DeepSeek 密钥设置界面
│  ├─ daily_phrase/              今日花语面板、请求服务与数据模型
│  └─ emotion_support/           情绪解语请求、结构化结果与校验
├─ models/                       回忆、心情、纪念日和专注数据模型
├─ pages/                        五个主标签、引导页与横屏时钟
├─ services/                     SQLite、图片、音频、统计及原生通信
├─ theme/                        全局色彩、字体与主题
└─ widgets/                      花园背景、绣球花、蝴蝶及通用组件
android/                         Kotlin 原生计时、通知与凭据模块
test/                            模型、统计、计时桥与白噪音测试
```

## 技术栈

- Flutter、Dart
- Kotlin、Android SDK、MethodChannel
- DeepSeek Chat Completions API、HTTPS、结构化 JSON
- SQLite、sqflite、应用私有文件目录
- Android Keystore、AES-GCM、AtomicFile
- audioplayers、image_picker
- Gradle、固定签名、自动递增版本号

## 测试与质量记录

项目按阶段建立测试资料，文档与源码一同纳入版本管理。第一阶段完成了功能范围梳理、需求追踪和 60 条测试用例设计，原有 31 项 Dart 测试通过。第二阶段新增 AI 模拟接口、SQLite 升级及 Android 模拟器应用流程测试：全量 Dart 测试 43 项通过，模拟器流程 1 项通过。阶段二只部分覆盖既有用例，真实服务、真机系统能力及长时间体验仍待后续验证。

- [测试计划与执行原则](docs/testing/01-测试计划.md)
- [需求追踪矩阵](docs/testing/02-需求追踪矩阵.md)
- [功能测试用例](docs/testing/03-测试用例.md)
- [阶段一基线执行记录](docs/testing/04-阶段一基线执行记录.md)
- [阶段二自动化执行报告](docs/testing/05-阶段二自动化执行报告.md)

本地复核命令：

```powershell
flutter test --no-pub -r expanded
flutter analyze --no-pub
```

## 本地运行

建议使用满足当前锁文件要求的 Flutter 3.44.0 或更高版本、Dart 3.12.0 或更高版本，并准备 Android SDK 与 Java 17。

```powershell
flutter pub get
flutter run
```

Android 构建脚本要求使用本地固定签名。公开仓库不应包含 `android/key.properties` 或 `.jks/.keystore` 文件，因此首次构建前需要自行创建签名文件，并在 `android/key.properties` 中填写本机配置：

```properties
storePassword=你的签名库密码
keyPassword=你的密钥密码
keyAlias=你的密钥别名
storeFile=你的签名文件路径
```

请勿提交上述文件或其中的真实内容。配置完成后可运行：

```powershell
flutter run
flutter build apk --release
```

## 使用 AI 功能

1. 在首页展开“今日花语”，或进入“心语／情绪解语”。
2. 首次使用时打开密钥设置，填写自己的 DeepSeek API Key。
3. 输入内容并点按生成；应用不会在启动时自动向 DeepSeek 发送请求。
4. 如需更换或移除密钥，可再次打开密钥设置进行操作。

使用 AI 功能需要网络和有效的 DeepSeek API Key；其他本地记录功能不依赖 DeepSeek。AI 请求可能受到账号额度、模型可用性、网络状态及第三方服务规则影响。

## 数据与隐私边界

- 长期记录默认只保存在当前设备，没有登录、云同步或业务服务器。
- 今日花语和情绪解语的输入及结果默认不写入本地数据库。
- 主动发起 AI 请求后，本次提交的文字会由 DeepSeek 处理；“本地不保存”不等于“第三方未处理”。
- 卸载 App 会清除 SQLite 数据库、应用私有目录中的照片以及本机保存的加密凭据，请提前备份重要内容。
- 两部手机分别安装时会形成两套独立数据，不会自动同步。

## 主要修改入口

- 本地随机短句：[assets/data/gentle_quotes.json](assets/data/gentle_quotes.json)
- 首页与功能入口：[lib/pages/home_page.dart](lib/pages/home_page.dart)
- 今日花语：[lib/features/daily_phrase/](lib/features/daily_phrase/)
- 情绪解语页面：[lib/pages/mailbox_page.dart](lib/pages/mailbox_page.dart)
- 情绪解语服务：[lib/features/emotion_support/](lib/features/emotion_support/)
- 数据库：[lib/services/local_database.dart](lib/services/local_database.dart)
- Android 原生能力：[android/app/src/main/kotlin/com/example/blue_hydrangea/](android/app/src/main/kotlin/com/example/blue_hydrangea/)
