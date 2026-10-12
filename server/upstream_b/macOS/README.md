# Mac / Xcode 运行版

适用于 macOS 13 或以上、Xcode 15 或以上、Python 3.12，Intel 和 Apple Silicon 均使用本机 Python。此次目标为 **My Mac**，不包含 iPhone 实时客户端迁移。

## 最快启动

1. 解压整个 ZIP，保留文件夹结构。安装 Python 3.12（python.org 官方 macOS 安装包，或已有 Homebrew 时执行 `brew install python@3.12`）。
2. 双击 `macOS/Setup.command`，安装项目 Python 依赖。首次需要网络。若文件没有执行权限，在解压目录执行 `bash macOS/Setup.command`。
3. 打开 `macOS/VoiceAssistantMac.xcodeproj`，Scheme 选 **VoiceAssistantMac**，设备选 **My Mac**，按 **⌘R**。
4. 等待本机服务自动启动。配置自动填好，按“开始粤语对话”，允许 macOS 和页面的麦克风权限。

无需重新输入 API Key，无需单独手动启动后端。默认采用本机 ad-hoc 签名，不要求先配置开发者 Team。首次打开 Xcode 自身的安装/许可步骤由 Mac 使用者完成。

若想先测原页面，也可双击 `macOS/Run-in-Browser.command`，自动启动服务并打开系统浏览器。浏览器版结束时按终端 Control-C 关闭服务。若 WebKit 收音有设备兼容问题，用浏览器版测试相同后端，不能将其视为原生壳已通过验收。

## 保留的核心功能

- 豆包流式 ASR → 方舟结构化理解 → 原有范围限制和业务逻辑 → 豆包粤语 TTS。
- 连续粤语对话、插话打断、文字输入、确认卡、单次十分钟上限。
- 香港天文台北区测站实况、北区雨量、全港预报及当前警告；原有新鲜度校验保持不变。
- 当前小何 2.0 女声、语速、模型与资源配置均从正在运行的 Windows 服务导出。
- 业务操作仍为既有演示数据，原本未接入的真实交通、账号和邀请不会因为迁移就变成真实功能。

`backend/assistant/` 和 `windows/web/` 按原文件逐字节复制，完整性记录在 `CORE-SHA256.json`。目录名 windows/web 是原代码的文件定位方式，不表示只能在 Windows 上运行。没有换成旧的 iOS 按句识别版本。

## 配置与文件位置

按用户明确要求，ZIP 的 `Private/voice-config.json` 包含当前实际使用的豆包语音 Key、火山方舟 Key，以及全部运行参数。不会在本文或源码里打印 Key；没有添加过期、未使用的历史 Key。

这份 ZIP 是含凭证的私有交付包，只交给你信任的朋友，不适合公开上传 GitHub。其内 `.gitignore` 排除了 Private 和本地运行环境。配置文件保留在解压目录外部资源中，不编译到 Swift 源码或 App Bundle。程序每次启动读取它，页面改动仍只保存到该次后端内存；要持久更换参数可修改该 JSON。

页面的“清空凭证”只清空该次运行内存，不删除你要求随包交付的 JSON；再次启动会重新读入。若要彻底移除，需由你删除 Private 中的配置文件。

Mac App 使用 SwiftUI + WKWebView 承载原页面，启动项目 `.venv` 中的 Python，仅监听 `127.0.0.1` 的自动空闲端口。关闭最后一个窗口或退出 App 会停止它创建的后端；不接管其他服务。外部天文台链接交给系统浏览器；仅允许本机页面请求麦克风，不允许摄像头。

这是从源代码目录运行的开发交付，**不能仅复制编译后的 .app 脱离项目目录使用**。移动整个解压目录后重新运行 Setup 并重新构建（Python 虚拟环境不能跨目录复制）。不含可公开分发的公证 .dmg，也不是 App Store 包。

## 验证边界

交付环境是 Windows，没有 Xcode/macOS SDK。已对后端和前端做已有自动测试，并用新 Mac 启动器测试真实 HTTP 启动、读取测试配置及关闭清理；这些不等于 Xcode 编译或 Mac 麦克风实测通过。

本次共核对 19 个核心文件哈希，79 项后端测试通过，原前端状态与音频重采样测试通过。包内 `ios/` 是保留供结构测试使用的旧版 iOS 源码；这次请只打开上述 macOS 工程，不用旧的 VoiceAssistantDemo iPhone 工程。

Mac 编译验证：

```sh
xcodebuild -project macOS/VoiceAssistantMac.xcodeproj -scheme VoiceAssistantMac -configuration Debug -destination 'platform=macOS' build
```

核心校验及测试：

```sh
.venv/bin/python tools/verify_mac_delivery.py
.venv/bin/python tools/verify_backend.py
```

真人试用顺序：问“你好” → “北区今日天气点呀” → “听日呢” → 回答时插话 → 测试医疗/投资拒答 → 关闭窗口确认麦克风释放。音色自然程度、扬声器回声和老人语速需要真实设备验证。
