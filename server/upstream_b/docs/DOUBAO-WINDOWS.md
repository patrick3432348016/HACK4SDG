# 全豆包实时粤语助手 · Windows 联调

日期：2026-10-12，Asia/Shanghai。状态：真实 ASR → 方舟 → TTS 合成语音回环已通过，用户反馈对话已接通；已接入香港天文台天气。老人真人录音、外放回声、延迟分位数与 iPhone 集成仍需独立验收。

## 当前选择与范围

用户要求：连续粤语交谈，面向老人，只回答散步 App 相关问题；医疗用药、投资、政治、色情及其他无关话题不展开。暂不涉及碰一碰。成员 A 的真实 App 接入由朋友完成。

当前采用全豆包模块化链路：ASR 2.0 双向流式优化接口 → 方舟豆包模型结构化路由 → 受限业务回复 → TTS 2.0 流式音频。**本版没有调用 Seeduplex 3.0 端到端接口，也不把独立 ASR/TTS 的粤语支持当作 Seeduplex 的测试证据。** 这样可以在播放前限制回复内容，代价是不能自由闲聊、回复表达较固定，且多阶段延迟需要实际测量。

用户已明确允许散步出行相关天气、交通。天气按用户要求接入香港北区：测站实况、北区雨量、全港预报及当前警告；交通尚未接入实时数据，固定说明资料未接通，不输出班次或路线猜测。社区榜、个人记录同样不虚构真实情况。邀请、集合点、请假、昵称和月报复用已有后端联调数据，所有写操作都要点确认卡，并明确为测试操作。

## 你需要准备什么

1. **豆包语音新版 API Key**：需要拥有流式 ASR 和 TTS 的权限。旧版也可填写 App ID 与 Access Token，二选一。
2. **火山方舟 API Key**，以及已开通、支持 JSON 输出的**豆包文本模型 ID 或 Endpoint ID**。不是“豆包 App 登录”，也不假设与语音 Key 通用。
3. **支持粤语的音色 ID**：从语音控制台音色库获取。代码传入 `explicit_dialect: yue`；实际音色是否支持此参数需真实调用确认。资源默认 `seed-tts-2.0`，复刻音色可选 `seed-icl-2.0`。
4. ASR 默认 `volc.seedasr.sauc.duration`（2.0 小时版）；也可选已开通的并发版或旧版。不能把端到端实时对话资源直接填到此处。

**不用把 Key 发到聊天或提交 GitHub**，直接填本机页面的密码框。点击「保存到本机服务」后，配置仅保存在本机服务进程内存中，同一台电脑刷新页面或换浏览器会自动填入；关闭或重启服务后清空。未保存的手动编辑仍会在刷新后丢失。页面不写 localStorage、Cookie 或配置文件。服务日志不输出凭证、录音、转写文本或上游原始错误。清空按钮会删除本页凭证及服务中已保存的配置；其他已打开页面需刷新才能清除旧副本。此功能仅用于本机联调，不适用于共享或公开部署。

## 启动和操作

当前电脑已经具备 Python 依赖。双击 `windows/Start-Windows.cmd`，用 Edge 或 Chrome 打开 `http://127.0.0.1:8765`。

换电脑：安装 Python 3.12，执行 `python -m pip install -r backend/requirements.txt -c backend/constraints.txt` 后再运行脚本。

- 无 API：可点“只检查麦克风”，检查音量和录音权限，声音不上传；点“检查本地拒答规则”验证固定规则。这两项都不是语音识别或豆包推理。
- 有 API：填写参数，点“开始粤语对话”。麦克风持续采集，云端判定句末后自动回应，不必每句按停止。识别通道建立后才显示已连接；这不代表方舟/TTS权限已验证，首个完整对话仍可能暴露配置问题。
- 插话：ASR 识别到新的语句内容时停止旧播报、取消旧生成；也可手动点“打断播报”。本地音量波动不会取消等待中的回复。声音播放队列按 turn_id 隔离，旧数据不能恢复播放。
- 慢速讲话：可将句末等待调为 1.8 或 2.5 秒，实际判停效果由供应商及网络决定。
- 页面切后台、结束对话、设备断开或连接错误都会停止本地收音。单次最多 10 分钟，不能无人值守无限调用。重新连接会开始新的业务会话。
- 回声消除依赖浏览器及设备；初次验证建议使用耳机，再测外放，不能把音量阈值当作可靠的说话人识别。

服务只监听本机；当前测试壳不提供公网认证或 iPhone 网络接入。正式接入需 HTTPS/WSS、登录认证、后端托管密钥和 A 的业务接口，不能直接把这个本机会话令牌机制搬到生产。

## 回答限制的实现

1. 明显受限关键词直接返回固定拒答；明确紧急求助优先固定求助提示。
2. 其余输入交给豆包选择有限 topic 和 Command JSON。模型返回自由回复、额外字段或错误结构时拒绝执行。
3. 播报内容由固定粤语句子和经过字段校验的天文台官方天气资料生成，**不播放模型自由文本，不朗读用户输入的昵称或任意联系人文本**。用户核对业务详细信息需要看确认卡。
4. 模型判为业务操作后也必须走现有参数校验、候选选择、确认及幂等处理。说“确认”不会自动执行写操作。
5. 无真实资料明确提示缺失。没有静态虚构天气，没有自动联网搜索，没有 Azure/Qwen 回退，也没有假转写。

限制：语义分类、粤语识别、意图与参数提取都可能出错；固定回复限制了输出范围，不能证明模型绝不会错分。紧急求助只提供提示，不实际拨号，不取代紧急服务。联系人、地名和其他动态资料作为界面数据展示，未作为任意可播报文本使用。

## 音频与对话协议（给 iOS 接入者）

输入：16 kHz、单声道、PCM16 小端，200 ms / 6400 字节。网页 AudioWorklet 持续转换设备音频并发送 WebSocket 二进制帧；不是停止后上传 WAV。

本机 `/windows/realtime` 第一条 JSON 为 `{token, config}`，config 字段见 `assistant/doubao.py:DoubaoConfig`。这是 Windows 联调专用配置方式，生产客户端应只发送登录凭证。

后续客户端消息：PCM 二进制；或 `{type:"text", text}`、`{type:"interrupt"}`、`{type:"stop"}`；业务卡片使用 `{type:"action", kind:"choice", choice_kind:"contact"|"place", value}` 和 `{type:"action", kind:"confirm"|"cancel"}`。

服务端：`ready`、`transcript {text,final}`、`interrupted {turn_id}`、`thinking`、`answer {text,policy,business}`、`audio {turn_id,data,sample_rate:24000}`、`answer_done`、`turn_error`、`error`。data 为 base64 PCM16 单声道；按 turn_id 丢弃旧包，打断时同时清除已排队声音。只对 ASR definite 分句触发响应，累计返回的旧句不得重复执行。

界面耗时是“最终识别文字到客户端收到首音频”，**不包含说话结束前后的识别判停过程**，不能标为完整端到端延迟。

## 验证与真实验收

自动检查：`python tools/verify_backend.py`、`node tools/test_capture.cjs`、`node tools/test_voice_ui.cjs`。

新增检查涵盖：二进制 ASR 帧、截断/超量解压拒绝、重复最终句去重、供应商错误脱敏、凭证缺失和跨站连接拒绝、拒答/紧急求助优先级、模型自由文本不能成为播报、写入需确认、模拟 ASR 到音频的 WebSocket 流程、打断后旧音频丢弃、迟到麦克风授权释放。**合成样本与 MockTransport 不是实际云端验收。**

接入凭证后逐项实测并记录失败，不给未测指标填写“通过”：

| 场景 | 验收内容 |
|---|---|
| 香港粤语、老人慢速及停顿 | 听懂意思，不抢话；人名、时间错了会追问/核对 |
| 约街坊 → 补充时间 → 选地点 → 确认 | 完整流程；只保存测试操作 |
| 医疗、投资、政治、色情、无关故事及伪装业务的越界请求 | 只播固定范围提示，不能读出自由生成回答 |
| 北区天气 | 真实测站标地点时间；全港预报不得称北区专属；未来日期不读当前温度；资料失效则提示 |
| 交通 | 没数据就说明缺失 |
| 打断、快速连续说话、断网、切后台 | 旧声音不重播、不重复操作、麦克风释放 |
| 5 分钟连续对话 | 无音频队列增长、重复最终句或连接泄漏 |
| 首个完整对话 | 分别确认 ASR、方舟、TTS 权限及音色；统计真实时延 |

## 官方资料（2026-10-12 查阅）

- [豆包 ASR 双向流式接口与二进制协议](https://docs.volcengine.com/docs/DoubaoVoice/LargemodelstreamingautomaticspeechrecognitionAPI?lang=zh)
- [豆包单向流式 TTS HTTP](https://docs.volcengine.com/docs/DoubaoVoice/unidirectional-streaming-text-to-speech-http?lang=zh)
- [方舟结构化工具调用](https://docs.volcengine.com/docs/ark/function-calling?lang=zh)
- [豆包端到端实时语音旧版接口，区别于本版链路](https://docs.volcengine.com/docs/DoubaoVoice/End-to-endreal-timespeechlargemodelAPIaccessdocument?lang=zh)
- [Seeduplex 3.0 接入文档，当前未实现](https://docs.volcengine.com/docs/DoubaoVoice/access-mustread?lang=zh)

新旧 TTS 文档的方言音色描述不同，按实际开通版本和控制台音色能力验证，不将普通话音色默认视为粤语音色。
