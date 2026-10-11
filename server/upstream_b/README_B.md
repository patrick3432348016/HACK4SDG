# 成员 B：出行语音助手

可独立交付给原生 iPhone App 的功能模块：**Swift 包 + SwiftUI 联调 App + Python/FastAPI 服务**。不包含碰一碰，不重建成员 A 的界面、账号系统或数据库。

**当前交付是可运行的后端及待 Mac 编译验收的 iOS 源码，不是已验证上线的 App。** 用户明确暂缓真实 API 验证；尚未验证 Azure/Qwen 的真实效果、iPhone 麦克风行为或生产业务接口。生产模式在配置不全时拒绝启动，不能把测试数据发布成真实服务。

## 交付内容

| 目录 | 用途 |
|---|---|
| `backend/` | 语音及模型适配器、业务流程、确认状态、部署配置、自动测试 |
| `ios/` | 可直接导入 Xcode 的 `MobilityAssistant` Swift 包，最低 iOS 17 |
| `ios/Demo/VoiceAssistantDemo.xcodeproj` | 独立 iPhone 联调壳，不依赖 A 的工程 |
| `docs/INTEGRATION.md` | 给 A 的接入步骤和业务接口契约 |
| `docs/DEPLOYMENT.md` | API 配置、生产部署、数据保留和上线门槛 |
| `docs/VALIDATION.md` | 已验证项、未验证项与真机验收表 |
| `.github/workflows/assistant.yml` | Linux 后端测试、Mac Swift 测试和 iOS Debug/Release 编译 |

把本目录**里面的全部内容**上传到 GitHub 仓库根目录，包括 `.github`。不需要上传外层碰一碰工程，也不需要上传 `.env`、`data/` 或真实录音。CI 会在 GitHub 的 Mac 运行器验证 iOS 编译；CI 成功也不能替代 iPhone 真机验收。

## 不配置 API 也能验证什么

- 文字约人 → 明确联系人/日期/时间/步行上限 → 集合点选择 → 核对确认 → 保存**测试操作**。
- 文字请假和改名，均需要显式确认；取消不会产生业务写入。
- 生成今日一句、地标昵称候选、月报；示例统计和地点均明确标注虚构。
- 天气数据缺失时如实提示，不编造天气。
- 实际录音权限和采集（需 iPhone 验证）；没有 API 时返回“未配置”，**不会把录音替换成预设识别文本**。
- 手机已安装相应音色时，可使用系统语音真实播报；界面明确说明未使用云端播报。

没有 API 时，文字解析是有限规则，用于验证联调流程，不代表真实 AI 理解能力。测试语句示例：

```text
约陈伯明天下午四点散步，遮荫优先，最多15分钟
約陳伯聽日下晝四點行下，唔好咁晒，最多15分钟
明天请假
改名为小明
散步建议
给社区花园起名
今日一句
生成月报
```

## 朋友在 Mac 上最快跑通

1. 安装 Python 3.12 和可支持测试手机系统的 Xcode。进入 `backend`，运行：

   ```sh
   python3.12 -m venv .venv
   source .venv/bin/activate
   python -m pip install -r requirements.txt -c constraints.txt
   python -m unittest discover -s tests -v
   python -m uvicorn assistant.app:create_app --factory --host 0.0.0.0 --port 8000 --no-access-log
   ```

   本步骤只用于可信局域网的联调。默认模式 `demo`，令牌 `local-demo-only`。不要把默认令牌服务直接暴露到公网。Windows 上可用 `python -m venv .venv` 和 `.venv\Scripts\Activate.ps1`。

2. 双击 `ios/Demo/VoiceAssistantDemo.xcodeproj`。在 Signing & Capabilities 选择自己的 Team；必要时修改 Bundle Identifier。选择 iPhone，点击 Run。
3. 手机与电脑连接同一 Wi-Fi。App 服务地址填写 `http://电脑局域网IP:8000`（例如 `http://192.168.1.20:8000`），令牌填 `local-demo-only`。**真机不能填 localhost**；模拟器可使用 `http://localhost:8000`。
4. 账号标识保持 `demo-user`，点击连接，选择文字示例，完成地点选择和确认。
5. 测试麦克风拒绝/允许、30秒上限、放弃录音、切后台，以及系统粤语和普通话播报。

Debug 联调壳允许 HTTP，**Release 不允许**。A 的正式 App 不应复制 Debug 的 ATS 放宽配置。录音转写后先填入文本框供用户校对，不自动执行指令。

## 工程验证命令

一条命令完成后端测试、结构检查及临时服务的真实 HTTP 冒烟，不使用已有 API 密钥，不污染联调数据库：

```sh
python tools/verify_backend.py
```

在本目录运行结构检查和真实 HTTP 冒烟（后端需已启动）：

```sh
python tools/check_delivery.py
python tools/smoke.py --url http://127.0.0.1:8000
```

在 Mac 上运行：

```sh
swift test --package-path ios
xcodebuild -project ios/Demo/VoiceAssistantDemo.xcodeproj -scheme VoiceAssistantDemo -configuration Debug -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
xcodebuild -project ios/Demo/VoiceAssistantDemo.xcodeproj -scheme VoiceAssistantDemo -configuration Release -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
```

## 产品边界

- “约人成功”分成**邀请已发送**和**对方已接受**；B 只负责前者，不能凭一次调用显示双方约会已成立。
- 只比较**集合点**遮荫和双方步行时间，不宣称路线遮荫、减排、健康收益或医学安全。
- 推荐规则：过滤非明确开放、步行数据不全或超过用户上限的地点；要求遮荫时过滤无有效遮荫数据的地点，按遮荫比例降序，再按双方较长步行时间升序。未要求遮荫时先最小化双方较长步行时间。无随机评分或未验证权重。
- 遮荫数据需来源和覆盖指定时刻的有效区间；天气采用有来源且不超过两小时的数据。A 必须提供适用于请求时刻的开放及步行信息。
- 月报默认上一个完整自然月，以香港时区划分；A 需声明活动记录覆盖区间，缺失/部分数据不会被当成零活动。所有次数、分钟和米数由程序计算，模型不能改写数字。
- 地标昵称只是候选，不自动改名真实地图地点。请假/昵称写入由 A 的业务后端执行。
- 确认卡10分钟有效。修改请求使旧卡失效；并发重复确认只有一次写调用；超时后只查询原操作，不盲目重试。

## 官方参考

- [Azure 短音频识别接口](https://learn.microsoft.com/en-us/azure/ai-services/speech-service/rest-speech-to-text-short)
- [Azure 播报接口](https://learn.microsoft.com/en-us/azure/ai-services/speech-service/rest-text-to-speech)
- [Azure 语言支持](https://learn.microsoft.com/en-us/azure/ai-services/speech-service/language-support)
- [Qwen 结构化输出](https://help.aliyun.com/en/model-studio/qwen-structured-output)
- [Apple AVAudioRecorder](https://developer.apple.com/documentation/avfaudio/avaudiorecorder)

本实现采用按键结束后上传短录音的方式，不依赖持续实时对话；音频上限30秒，低于短音频 REST 的60秒限制。
