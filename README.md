# 给你的蓝色绣球花

一个接入Deepseek、只属于两个人的 Flutter Android App。它不是关系管理工具，而是一份可以长久保存的温柔礼物。

## 已实现

- 花园首页、每日问候与“点开一只蝴蝶”随机短句
- “我眼里的你”温柔小事记录，可附本地照片
- 五种心情入口的绣球花信箱
- “如果你现在不开心”安静陪伴页
- 回忆相册与时间轴，可记录照片、日期、地点和一句话
- 每日心情选择与最近 30 条记录
- SQLite 本地数据库、图片永久复制至 App 私有目录
- 原生绘制的蓝色绣球花、蝴蝶、柔光及轻量动画
- 接入deepseek、实现情绪安抚、情感问题分析

## 项目结构

```text
assets/data/            本地随机短句
lib/models/             数据模型
lib/pages/              六个核心页面与添加表单
lib/services/           SQLite、图片保存、短句读取
lib/theme/              色彩与全局主题
lib/widgets/            花园背景、绣球花绘制、通用卡片
android/                Android 工程配置
test/                   基础模型测试
```

## 运行

需要当前稳定版 Flutter（内含 Dart 3.8 或更高版本）、Android SDK，以及一台 Android 7.0（API 24）或更高版本的设备/模拟器。

当前交付目录不包含二进制格式的 Gradle Wrapper JAR。安装 Flutter 后，先用官方模板补齐一次本机 Android Wrapper，再运行项目：

```powershell
flutter create --platforms=android .
flutter pub get
flutter run
```

`flutter create` 用于按你安装的 Flutter 版本补齐平台脚手架。若命令提示将覆盖 Android 配置，请先备份 `android/app/src/main/AndroidManifest.xml`、`android/app/build.gradle.kts` 和 `android/app/src/main/res`；Dart 业务源码与本地文案不会受影响。

## 个性化文案

- 随机短句：[assets/data/gentle_quotes.json](assets/data/gentle_quotes.json)
- 信箱初始信件与示例数据：[lib/services/local_database.dart](lib/services/local_database.dart)
- 首页每日问候：[lib/pages/home_page.dart](lib/pages/home_page.dart)

所有新增内容都会保存在设备本地。卸载 App 会一并清除数据库和复制到 App 私有目录的照片，请在需要时先备份。
