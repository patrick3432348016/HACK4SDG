# 组员 B 嘅豆包密钥（只喺私有仓库）

`doubao.json`：豆包语音 Key、火山方舟 Key、模型、音色（B 的 VoiceAssistant-Mac `Private/voice-config.json`）。
用户 2026-10-12 决定放入**私有**仓库，方便组员内部测试 AI。

- **唔好将仓库改成公开，唔好将呢个文件发去其他地方**：密钥扣 B 嘅豆包账户嘅钱。
- `tools/voice_server.sh` 自动用：先揾 `~/Desktop/HACK/voice-runtime/doubao.json`（本机另放嘅），冇就用呢个。
- 想换密钥：改呢个文件；想停用：喺火山引擎控制台作废旧 Key。
