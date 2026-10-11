# 配置与部署

## 先本地联调，后接真实 API

不配置任何环境变量时：`ASSISTANT_MODE=demo`，文字由有限规则解析，所有业务数据与写入为本地测试数据。Azure/Qwen 有完整配置时，可在 demo 模式调用真实供应商，但业务数据仍是虚构；界面分别显示两种能力，不能把测试模式整体标成生产验证通过。

| 变量 | 说明 |
|---|---|
| `ASSISTANT_MODE` | `demo` 或 `production` |
| `ASSISTANT_DATABASE` | SQLite 路径，默认 `data/assistant.sqlite3` |
| `DEMO_TOKEN` | 本地联调令牌，默认值不可用于公开服务 |
| `AZURE_SPEECH_KEY` | 仅放服务端的 Speech key |
| `AZURE_STT_URL` | 完整识别 HTTPS URL，不包含 language 参数，由代码追加 |
| `AZURE_TTS_URL` | 完整语音合成 HTTPS URL |
| `QWEN_API_KEY` | 仅放服务端的模型 key |
| `QWEN_BASE_URL` | 与 key 地域匹配的兼容接口根地址，不含 `/chat/completions` |
| `QWEN_MODEL` | 实际账号可用、支持 JSON Object 输出的文本模型 ID |
| `BUSINESS_BASE_URL` | A 的 HTTPS 业务后端根地址，接口见 INTEGRATION.md |

端点必须为 HTTPS，不允许 URL 内账号密码、查询字符串或 fragment。没有任何自动猜测账号地域或模型名的行为。实际可用模型、音色和配额需开通账号后验证。

Azure 录音为16kHz、单声道、PCM16 WAV，上限30秒；转写不流式返回。合成采用粤语 `zh-HK-HiuMaanNeural`、普通话 `zh-CN-XiaoxiaoNeural`，需核验所选资源当前可用音色。文本在构造 SSML 前转义，不能作为 SSML 标签执行。

Qwen 使用 `response_format=json_object`，程序随后严格验证字段和类型，并由业务数据校验实际可执行性。JSON 格式有效不能证明用户意图正确。未授权文本不能改写系统指令或直接执行数据库操作。

## 启动方式

原生 Python 启动不自动读取 `.env`。通过进程环境或秘密管理服务传入变量；Docker Compose 则读取 `backend/.env`。

```sh
cd backend
cp .env.example .env
# 编辑 .env；首次联调保留 demo，不填写真实 key 也能跑文字流程。
docker compose up --build -d
docker compose logs --tail=50
```

Compose 只暴露 `127.0.0.1:8000`，需 TLS 反向代理对外提供 HTTPS。本机 Docker Desktop 未运行，因此此构建路径尚未实际验证。后端已通过本机 Python 启动及 HTTP 冒烟。

部署使用**一个 Uvicorn worker、一个服务实例**和持久卷。SQLite 事务保护确认认领；当前内存限流器不是跨节点限流方案。扩容前迁移会话/草稿数据库与统一限流，不能直接增加无共享状态的副本。

## 公网入口要求

- TLS 证书、有效的 HTTPS 域名；生产模式拒绝明文业务请求（`/healthz` 仅供内网存活检查）。
- 代理设置请求体上限2MB、请求读取超时、连接上限和按来源/用户的全局限流。应用单用户令牌限流默认60次/分钟，只是第二道限制，不能抵御更换无效令牌的请求。
- 仅信任真实反向代理设置的转发头。Uvicorn 的 `FORWARDED_ALLOW_IPS` 按实际代理 IP 设置，不可对不可信公网来源设为 `*`；容器网络地址不是默认127.0.0.1，需部署者明确配置。
- 不直接对公网开放 Uvicorn 端口。禁止在访问日志中保存 Authorization、音频、用户文字或业务完整响应；示例启动禁用 access log，应用错误只记录 request_id。
- 不启用任意来源的 CORS。原生 App 不需要 CORS；未来网页客户端需要明确来源列表。
- 部署后检查 `/healthz`、经过真实登录的 `/v1/capabilities` 和业务全流程。存活检查只代表进程正常，不代表供应商、数据质量、权限或业务链路正常。

## 数据保留及恢复

- 服务端原始音频只在内存处理；不保存转写历史或原始对话全文到数据库。
- 结构化会话含用户意图/名字，空闲24小时后不可使用，每小时或重启时清理。
- 确认操作、状态和回执保留30天；`executing/uncertain` 状态为避免误重复保留到权威核查解决。运营方需安排人工核查，不可无限搁置。
- SQLite 卷及备份属于用户数据，需最小权限和加密磁盘。按组织要求设定备份/删除流程；删除请求遇到未决操作时先核查，然后按既定政策处理，不能冒充“已删除且无业务影响”。
- iOS 原始录音使用应用临时目录，完成或主动放弃后删除；系统异常终止时可能留下临时文件，下一次录音前清理该模块的过期录音文件。
- iOS token 保存在联调壳的 Keychain，正式 App 应沿用 A 的认证存储；UserDefaults 只存待核查操作 ID，不存 token。

## API 开通后必须补做的上线验收

1. 真实粤语和普通话录音：至少覆盖人名、口音、吵杂环境、日期修改和识别失败；统计实际意图/字段准确率和耗时，不把文档“支持粤语”当作验收。
2. 真机权限拒绝、录音中断、自动停止、播报语言、后台取消和杀进程恢复。
3. A 的鉴权、跨用户隔离、数据时间区间、重复写入去重、超时后查询和版本冲突。
4. 同一地点候选集与“仅看步行时间”基线比较；遮荫数据经过 A 的独立验证，不能用本模块的排序测试证明3D模型准确。
5. 容器构建、TLS代理、持久卷重启、备份恢复与入口限流。

未通过上述项目，不能将源码交付、测试模式或 MockTransport 测试描述成“已上线可用”。
