# 接入主 App：给成员 A

## iOS 接入

在 Xcode → Add Package Dependencies → Add Local 中选 `ios` 文件夹，把 `MobilityAssistant` 产品加入主 App target。也可将该包单独发布到团队 Git 仓库后作为包依赖。最低 iOS 17，无第三方 Swift 依赖。

在 A 的 Info.plist 添加 `NSMicrophoneUsageDescription`，说明录音会传给配置的服务处理。原始音频不会写入 B 后端持久存储。使用 HTTPS；不要复制联调壳的 Debug ATS 放宽设置。

```swift
import MobilityAssistant
import SwiftUI

// 在 MainActor 创建并由 A 的视图通过 StateObject/稳定的实例持有。
let client = try AssistantClient(baseURL: URL(string: "https://assistant.example.com")!) {
    // 每次请求读取 A 当前登录令牌，支持刷新。
    try await yourAuthManager.currentAccessToken()
}
let model = AssistantViewModel(
    client: client,
    identityScope: "production:" + yourAuthenticatedUserID
)
// 可直接使用联调 UI，或绑定 model 构建 A 的正式界面。
AssistantPanel(model: model)
```

示例中的 `yourAuthManager` 和 `yourAuthenticatedUserID` 是 A 的现有登录系统，不是包内符号。不要把 Azure、Qwen 或后端管理员密钥放进 App。B 的默认 `local-demo-only` 只用于本地测试。

`identityScope` 必须同时隔离环境和登录用户，不能依赖每次刷新的 token 值。模型会在请求执行前持久化待确认操作 ID；超时或杀进程后，通过此 ID 查询原结果。换账号时重建 ViewModel。挂起/离开时调用 `backgrounded()`（使用 AssistantPanel 时已自动处理）。不能把取消网络请求当成撤回服务器业务操作。

文字/录音开始 → 转写文本核对 → 发送 → 联系人/地点选择 → 确认卡 → 确认或取消。用户可以修改文字继续对话；需要确认的业务操作不接受模型自动执行。

## B 暴露给 App 的 HTTP API

所有 `/v1/` 请求均需 `Authorization: Bearer <A登录令牌>`。生产模式将令牌交给 A 验证，B 不接受客户端自报 user_id。测试模式只接受 `DEMO_TOKEN` 并映射为 `demo-user`。

| 方法及路径 | 输入 | 输出/用途 |
|---|---|---|
| `GET /healthz` | 无鉴权 | 进程存活；不代表供应商可用 |
| `GET /v1/capabilities` | 登录令牌 | 测试/生产模式，语音和模型是否已配置 |
| `POST /v1/speech/transcribe?locale=zh-HK` | `audio/wav` 原始字节，16kHz、单声道、PCM16，0.2–30秒 | `text`, `locale`, `duration_seconds`, `source` |
| `POST /v1/speech/synthesize` | `{"text":"你好","locale":"zh-HK"}` | MP3 音频 |
| `POST /v1/assistant/turn` | `{"text":"...","locale":"zh-HK","conversation_id":null}` | 理解指令、今日一句、地标起名、地点推荐、建议、月报统一入口 |
| `POST /v1/conversations/{id}/choice` | `{"kind":"contact或place","value":"服务返回的ID"}` | 选择后继续处理；不能提交界面未提供的选项 |
| `POST /v1/drafts/{id}/confirm` | 无 | 原子认领并提交操作；重复调用不重复写入 |
| `POST /v1/drafts/{id}/cancel` | 无 | 只取消未提交的确认卡 |
| `POST /v1/drafts/{id}/reconcile` | 无 | 只查询，绝不把未提交卡变成已提交操作 |

语言仅支持 `zh-HK`/`zh-CN`；时间使用带时区 ISO8601；服务端以香港时间解析相对时间。会话和草稿 ID 是32位十六进制字符串。

统一业务回复：

```json
{
  "conversation_id": "32位ID",
  "status": "needs_confirmation",
  "message": "供界面显示的解释和确认内容",
  "speech_text": "可播报文字",
  "command": {"intent": "invite"},
  "choices": [],
  "draft_id": "32位ID或null",
  "data": {},
  "demo": true
}
```

`command` 实际包含完整 Command 模型字段，其余缺失字段为 null/false。不要从 `message` 推断成功；状态枚举为 `needs_input`、`choose_contact`、`choose_place`、`needs_confirmation`、`completed`、`cancelled`、`uncertain`、`info`。`info` 可能是建议或业务拒绝，须结合 `data.operation_status` 判断。只有 `completed` 表示获得成功回执。

统一错误：`{"error":{"code":"SPEECH_NOT_CONFIGURED","message":"...","request_id":"..."}}`。常见状态码：401 登录无效、409 过期/状态冲突、413 体积过大、422 参数或音频错误、429 本服务限流、502 上游格式/调用失败、503 未配置/不可用、504 上游超时。不要自动重试有副作用的操作。

## A 需要提供的业务 API

B 将原始用户 bearer token 转发给下面接口，**A 必须逐次鉴权和校验授权范围**。不接受 B 的测试身份来访问真实数据。

### 1. `GET /assistant/session`

成功返回 `{"user_id":"稳定的业务用户ID"}`；无效或无权访问返回401/403。不返回凭证或无关用户资料。

### 2. `GET /assistant/context?at=<ISO8601>`

只返回当前用户有权使用的最小上下文。`at` 是请求集合时刻；未指定活动时为当前时刻。

```json
{
  "version": "context-version-123",
  "contacts": [{"id":"c1","name":"陈伯","aliases":["陳伯"]}],
  "places": [{
    "id":"p1","name":"花园","description":"社区花园集合点",
    "is_open":true,"self_walk_minutes":8,
    "contact_walk_minutes":{"c1":10},
    "shade_fraction":0.8,
    "shade_valid_from":"2026-10-11T15:45:00+08:00",
    "shade_valid_until":"2026-10-11T16:30:00+08:00",
    "source":"A的遮荫模型v1，集合点区域比例"
  }],
  "weather": {
    "observed_at":"2026-10-10T10:00:00+08:00",
    "summary":"上游天气摘要",
    "source":"实际天气来源",
    "outdoor_warning":false
  },
  "walks":[{"day":"2026-09-20","minutes":30,"metres":1500}],
  "walk_coverage":{"start":"2026-09-01","end_exclusive":"2026-10-01"}
}
```

- `version` 应随影响操作有效性的业务数据变化。不能因为每次请求时间不同就无条件换版本，亦不能永不更新。
- `is_open` 是请求时刻的开放状态；未知用 null。步行时间来自 A 的路径计算或已声明的估计，单位分钟；不存在的数据不要填0。
- 遮荫比例仅表示集合点对应区域，来源和时间区间缺失时视为未知。若只有二值遮荫数据，可约定 0/1 并在来源中说明定义，不能当成精确面积比例宣传。
- 联系人同名允许，但 ID 必须唯一。只在明确同一人时配置别名；不要让模型猜身份。
- `weather` 可为 null。无天气数据时 B 返回缺失提示。天气摘要是 A 的可信数据，不交给模型改写。
- `walks` 为同意授权、已去重的活动记录（最多10000条）。`walk_coverage` 声明已经完整取得的日期区间（左闭右开）；只有它覆盖上一个完整自然月时，B 才返回 `data.report_available=true` 并计算月报。缺失或部分覆盖返回不可用提示，不能填零伪装无活动。完整覆盖且记录确为空时才返回零活动。以后可扩展独立聚合接口，但此版按上述契约实现。
- 用户选择的联系人 ID 会在后续补充时间/步行限制时保持并重新校验。若该 ID 不再可用，返回409 `CONTACT_CHANGED`，不能回退到另一位同名联系人。App 应提示用户重新开始邀请并选择当前联系人。

### 3. `POST /assistant/actions`

头部 `Idempotency-Key: <draft_id>`，请求：

```json
{
  "operation_id":"同一个draft_id",
  "expected_context_version":"context-version-123",
  "action": {
    "kind":"invite","contact_id":"c1","place_id":"p1",
    "starts_at":"2026-10-11T16:00:00+08:00",
    "max_walk_minutes":15,"prefer_shade":true
  }
}
```

另外两种 action：`{"kind":"leave","date":"2026-10-11"}`、`{"kind":"rename","new_name":"小明"}`。

A 在**一个原子业务事务**内验证用户权限、请求版本、日期、联系人、地点和约束，并按 `(user_id, operation_id)` 去重；相同 ID 不同 payload 必须拒绝。B 的 SQLite 只能防自身重复提交，不能替代 A 的幂等写入。

返回200 JSON：

- 完成：`{"status":"succeeded","receipt_id":"业务记录ID","message":"可选说明"}`。
- 确定未写入：`{"status":"rejected","receipt_id":null,"message":"业务拒绝"}`。
- 正在处理：`{"status":"pending","receipt_id":null,"message":"处理中"}`。

业务拒绝用明确的 `rejected` 回执。非2xx、断线或无效回执在 B 看来都无法证明“没有写入”，因此会标记结果不确定，而不会擅自重试。

### 4. `GET /assistant/actions/{operation_id}`

同样验证用户，返回上面的状态及回执；未查到返回200 `{"status":"not_found"}`。**`not_found` 不代表之前一定未写入**：B 保持不确定，不能从此自动再发一次写请求。A 必须提供权威处理状态或在主 App 内核查解决。已完成记录的去重和回执至少保留30天。

## 确认流程不变量

1. 联系人、地点都从业务数据解析为真实 ID；模型不能产生可直接执行的 ID。
2. 原始用户文字、结构化意图和 API 错误不能替代正式业务回执。
3. 重复确认和客户端重连不得产生第二次写操作。
4. 修改需求使旧确认卡失效，取消后不能执行；已提交的取消需 A 的独立撤回业务，不在此模块冒充完成。
5. 发生超时或杀进程后，界面恢复原操作 ID 并查询；不能仅清空错误再创建同一邀请。
