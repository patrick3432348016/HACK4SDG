"use strict";
const $ = id => document.getElementById(id);
let token, ws = null, context = null, mic = null, worklet = null, sink = null;
let connecting = false, connected = false, micOnly = false, shuttingDown = false, lifecycle = 0;
let turn = -1, blockedTurn = -1, nextPlay = 0, sources = new Set(), responsePending = false;
let transcriptAt = 0, firstAudio = true;
let importing = false, importGeneration = 0;
let configRevision = 0;
const fields = ["speechKey", "appId", "accessKey", "arkKey", "model", "speaker", "ttsResource", "asrResource", "pauseMs", "rate"];
function status(message, error = false) { $("status").textContent = message; $("status").classList.toggle("error", error); }
function phase(title, hint) { $("phase").textContent = title; if (hint) $("hint").textContent = hint; }
function controls() {
  $("connect").disabled = !token || connecting || connected || micOnly || shuttingDown || importing;
  $("stop").disabled = !connecting && !connected && !micOnly;
  $("micTest").disabled = !token || connecting || connected || micOnly || shuttingDown;
  $("send").disabled = !connected || !$("typed").value.trim();
  $("interrupt").disabled = !connected;
  $("clear").disabled = connecting || connected;
  $("saveConfig").disabled = !token || connecting || connected || importing;
  $("configFile").disabled = connecting || connected || importing;
  $("policyTest").disabled = !token || connected || connecting;
  fields.forEach(id => $(id).disabled = connecting || connected);
  $("choices").querySelectorAll("button").forEach(b => b.disabled = !connected || responsePending);
  $("connection").textContent = connected ? "豆包已连接" : connecting ? "正在连接" : micOnly ? "本地麦克风检查" : "等待配置";
  $("connection").classList.toggle("online", connected);
  $("orb").classList.toggle("active", connected || micOnly);
}
function config() {
  const value = {speech_key: $("speechKey").value.trim(), app_id: $("appId").value.trim(), access_key: $("accessKey").value.trim(),
    ark_key: $("arkKey").value.trim(), model: $("model").value.trim(), speaker: $("speaker").value.trim(),
    asr_resource: $("asrResource").value, tts_resource: $("ttsResource").value,
    end_window_ms: Number($("pauseMs").value), speech_rate: Number($("rate").value)};
  if ((!value.speech_key && !(value.app_id && value.access_key)) || !value.ark_key || !value.model || !value.speaker)
    throw new Error("请先填写语音凭证、方舟 API Key、豆包模型 ID 和支持粤语的音色 ID。");
  return value;
}
function configurationEdited() {
  configRevision++;
  if (connecting || connected) return;
  $("importStatus").textContent = "配置已修改，点击保存到本机服务可在刷新或换浏览器后自动填入。";
  try { config(); status("配置已填写，尚未连接。点击开始粤语对话后会开启麦克风并连接豆包。"); }
  catch (error) { status(error.message); }
}
fields.forEach(id => { $(id).oninput = configurationEdited; $(id).onchange = configurationEdited; });
function stopAudio() {
  for (const source of sources) { try { source.stop(); } catch {} }
  sources.clear(); nextPlay = 0; $("orb").classList.remove("speaking");
}
function interrupt() {
  stopAudio(); blockedTurn = turn; responsePending = false;
  if (ws?.readyState === WebSocket.OPEN) ws.send(JSON.stringify({type: "interrupt"}));
  phase("你继续讲", "已停止旧回答，正在听你的下一句话。"); controls();
}
async function microphone(local, generation) {
  if (!navigator.mediaDevices?.getUserMedia || !window.AudioWorkletNode) throw new Error("此浏览器不支持实时收音，请用 Windows Edge 或 Chrome 打开本机地址。");
  const stream = await navigator.mediaDevices.getUserMedia({audio: {channelCount: 1, echoCancellation: true, noiseSuppression: true, autoGainControl: true}});
  if (generation !== lifecycle) { stream.getTracks().forEach(t => t.stop()); return false; }
  mic = stream;
  const audio = new AudioContext({sampleRate: 16000}); context = audio; await audio.resume();
  await audio.audioWorklet.addModule("/capture.js");
  if (generation !== lifecycle) return false;
  worklet = new AudioWorkletNode(audio, "voice-capture");
  sink = audio.createGain(); sink.gain.value = 0;
  audio.createMediaStreamSource(mic).connect(worklet); worklet.connect(sink).connect(audio.destination);
  worklet.port.onmessage = ({data}) => {
    if (generation !== lifecycle) return;
    $("level").value = Math.min(1, data.rms * 5);
    if (local || !connected || ws?.readyState !== WebSocket.OPEN) return;
    if (ws.bufferedAmount > 128000) { status("网络发送积压，已结束连接，避免播放过时对话。", true); disconnect(); return; }
    // Volume alone cannot distinguish speech from noise. The backend interrupts
    // on a new ASR partial; acoustic onsets must not cancel a pending answer.
    ws.send(data.pcm);
  };
  mic.getAudioTracks()[0].onended = () => { status("麦克风连接已断开。", true); disconnect(); };
  return true;
}
async function disconnect() {
  lifecycle++;
  if (shuttingDown) return;
  shuttingDown = true; connected = false; connecting = false; micOnly = false;
  const old = ws; ws = null;
  if (old) { old.onclose = null; if (old.readyState === WebSocket.OPEN) old.send(JSON.stringify({type: "stop"})); old.close(); }
  stopAudio(); responsePending = false;
  mic?.getTracks().forEach(track => { track.onended = null; track.stop(); }); mic = null;
  if (worklet) { worklet.port.onmessage = null; worklet.disconnect(); worklet = null; }
  if (context && context.state !== "closed") await context.close(); context = null;
  $("level").value = 0; $("partial").textContent = "收音已停止";
  phase("对话已结束", "录音已关闭；需要时可以重新连接。"); shuttingDown = false; controls();
}
function bubble(who, text) {
  const chat = $("chat"); chat.querySelector(".empty")?.remove();
  const node = document.createElement("div"); node.className = `bubble ${who}`;
  const label = document.createElement("small"); label.textContent = who === "user" ? "你" : "街坊助手 · 业务短回复";
  node.append(label, document.createTextNode(text)); chat.append(node);
  while (chat.children.length > 40) chat.firstElementChild.remove(); chat.scrollTop = chat.scrollHeight;
}
function renderBusiness(data) {
  $("choices").replaceChildren(); $("businessEmpty").hidden = Boolean(data);
  $("business").textContent = data?.message || ""; $("businessJson").textContent = data ? JSON.stringify(data, null, 2) : "暂无请求";
  if (!data) return;
  const action = (label, params) => {
    const b = document.createElement("button"); b.className = "secondary"; b.textContent = label;
    b.onclick = () => { if (!connected || responsePending) return; responsePending = true; controls(); ws.send(JSON.stringify({type: "action", ...params})); };
    $("choices").append(b);
  };
  for (const choice of data.choices || []) action(`${choice.label}${choice.detail ? " · " + choice.detail : ""}`, {kind: "choice", choice_kind: data.status === "choose_contact" ? "contact" : "place", value: choice.id});
  if (data.status === "needs_confirmation") { action("核对无误，确认测试操作", {kind: "confirm"}); action("取消", {kind: "cancel"}); }
  controls();
}
function renderWeather(data) {
  if (!data) return;
  const card = $("weather"); card.replaceChildren();
  const line = (text, muted = false) => { const p = document.createElement("p"); p.textContent = text; if (muted) p.className = "muted"; card.append(p); };
  const at = value => new Date(value).toLocaleString("zh-HK", {timeZone: "Asia/Hong_Kong", hour12: false});
  line(`${data.requested_place} · 查询日期 ${data.date}`);
  for (const item of data.observations || []) line(`${item.station}测站 ${item.temperature_c}°C · ${at(item.recorded_at)}`);
  if (data.rainfall) line(`北区录得最高雨量 ${data.rainfall.max_mm} 毫米（${at(data.rainfall.from)} 至 ${at(data.rainfall.to)}）；这是过去雨量，不代表稍后会否下雨。`, true);
  if (data.forecast) {
    line(`全港预报参考 · ${data.forecast.period}`);
    line(data.forecast.description);
    if (data.forecast.min_c !== undefined) line(`全港预报气温 ${data.forecast.min_c}–${data.forecast.max_c}°C`);
    line(`预报发布：${at(data.forecast.updated_at)}`, true);
  }
  line(data.warnings?.length ? `当前警告：${data.warnings.map(w => w.name).join("、")}` : data.warnings_available ? "查询时警告摘要未列出生效警告；不代表出行没有风险。" : "未能确认最新天气警告。");
  for (const note of data.notes || []) line(note, true);
  line(`查询时间（香港）：${at(data.checked_at)}`, true);
}
function play(message) {
  if (!context || message.turn_id !== turn || message.turn_id <= blockedTurn) return;
  const raw = atob(message.data), bytes = Uint8Array.from(raw, c => c.charCodeAt(0));
  if (bytes.length % 2 || message.sample_rate !== 24000) throw new Error("收到无效播报数据。");
  const view = new DataView(bytes.buffer), buffer = context.createBuffer(1, bytes.length/2, 24000), channel = buffer.getChannelData(0);
  for (let i=0; i<channel.length; i++) channel[i] = view.getInt16(i*2, true)/32768;
  nextPlay = Math.max(context.currentTime + .04, nextPlay);
  if (nextPlay - context.currentTime > 50) throw new Error("播报队列过长，已停止播放。");
  const source = context.createBufferSource(); source.buffer = buffer; source.connect(context.destination); sources.add(source);
  source.onended = () => { sources.delete(source); if (!sources.size) { $("orb").classList.remove("speaking"); if (!responsePending && connected) phase("我喺度听", "你可以继续问 App 相关问题。"); } };
  source.start(nextPlay); nextPlay += buffer.duration; $("orb").classList.add("speaking"); phase("用粤语回答中", "你可以直接插话，或点击打断播报。");
  if (firstAudio) { firstAudio = false; $("metrics").textContent = `从最终识别到收到首段音频：${((performance.now()-transcriptAt)/1000).toFixed(2)} 秒（不含前面的识别判停时间）`; }
}
function event(message) {
  if (message.type === "ready") {
    connecting = false; connected = true; status("豆包识别通道已连接。请用粤语说话，句末停顿后自动回应。"); phase("我喺度听", "连续收音已开启，说完一句稍等就会回应。"); controls(); return;
  }
  if (message.type === "error") { status(`${message.message} [${message.code}]`, true); disconnect(); return; }
  if (message.type === "transcript") {
    $("partial").textContent = message.text;
    if (message.final) { bubble("user", message.text); transcriptAt = performance.now(); renderBusiness(null); }
    return;
  }
  if (message.type === "interrupted") { turn = message.turn_id; stopAudio(); responsePending = false; controls(); return; }
  if (message.turn_id !== turn || message.turn_id <= blockedTurn) return;
  if (message.type === "thinking") { responsePending = true; firstAudio = true; phase("正在准备回答", "已收到你讲嘅内容，稍等就会用粤语回答。"); status("已识别完成，正在生成业务回复…"); controls(); }
  if (message.type === "answer") { bubble("assistant", message.text); renderBusiness(message.business); renderWeather(message.weather); status(message.policy === "deny" ? "已按范围限制回复，没有展开无关话题。" : "回复已准备，等待粤语音频。"); }
  if (message.type === "audio") play(message);
  if (message.type === "answer_done") { responsePending = false; if (!sources.size) phase("我喺度听"); controls(); }
  if (message.type === "turn_error") { stopAudio(); responsePending = false; status(`${message.message} [${message.code}]`, true); phase("这次回应未完成", "可以继续讲话，或检查 API 配置后重连。"); controls(); }
}
$("connect").onclick = async () => {
  if (connecting || connected) return;
  let generation;
  try {
    const settings = config(); generation = ++lifecycle; connecting = true; turn = -1; blockedTurn = -1; controls(); renderBusiness(null);
    status("等待麦克风权限并连接豆包…"); if (!await microphone(false, generation)) return;
    if (!connecting || generation !== lifecycle) return;
    ws = new WebSocket(`${location.protocol === "https:" ? "wss:" : "ws:"}//${location.host}/windows/realtime`);
    const current = ws;
    ws.onopen = () => current.send(JSON.stringify({token, config: settings}));
    ws.onmessage = e => { if (current !== ws) return; try { event(JSON.parse(e.data)); } catch { status("消息处理失败，已停止本次对话。", true); disconnect(); } };
    ws.onerror = () => { if (current === ws) status("实时连接失败，请确认本机服务已启动。", true); };
    ws.onclose = () => { if (current === ws) { if (!$("status").classList.contains("error")) status("实时连接已关闭。请重新开始对话。"); disconnect(); } };
  } catch (error) {
    if (generation === undefined) { status(error.message, true); controls(); return; }
    if (generation !== undefined && generation !== lifecycle) return;
    const permissions = {NotAllowedError: "麦克风权限被拒绝，请在浏览器网站权限及 Windows 隐私设置中允许麦克风。", NotFoundError: "未检测到麦克风。", NotReadableError: "麦克风不可用，请检查设备或其他软件占用。"};
    status(permissions[error.name] || error.message, true); await disconnect();
  }
};
$("micTest").onclick = async () => { const generation = ++lifecycle; micOnly = true; controls(); try { if (!await microphone(true, generation)) return; phase("正在检查麦克风", "请讲话观察音量条。没有上传声音，也没有进行识别。"); status("这是本地设备检查；点击结束对话可关闭麦克风。"); } catch { if (generation !== lifecycle) return; status("无法打开麦克风，请检查浏览器和 Windows 的录音权限。", true); await disconnect(); } };
$("stop").onclick = () => { status("已主动结束对话。"); disconnect(); };
$("interrupt").onclick = interrupt;
$("typed").oninput = controls;
$("send").onclick = () => { const text = $("typed").value.trim(); if (!connected || !text) return; interrupt(); ws.send(JSON.stringify({type: "text", text})); $("typed").value = ""; controls(); };
$("typed").onkeydown = e => { if (e.key === "Enter" && !e.isComposing && !$("send").disabled) $("send").click(); };
function parseCredentialFile(text) {
  if (typeof text !== "string" || text.length > 65536) throw new Error("文件过大，请选择 64 KB 以内的配置文件。");
  text = text.replace(/^\uFEFF/, "").trim();
  let entries;
  if (text.startsWith("{")) {
    const data = JSON.parse(text);
    if (!data || Array.isArray(data) || typeof data !== "object") throw new Error();
    entries = Object.entries(data);
  } else {
    entries = text.split(/\r?\n/).filter(line => line.trim() && !line.trim().startsWith("#")).map(line => {
      const match = line.match(/^\s*([^:=：]+)\s*[:=：]\s*(.*?)\s*$/);
      if (!match) throw new Error();
      return [match[1], match[2]];
    });
  }
  const aliases = new Map(Object.entries({speechkey:"speechKey", speechapikey:"speechKey", arkkey:"arkKey", arkapikey:"arkKey",
    appid:"appId", accesskey:"accessKey", accesstoken:"accessKey", model:"model", modelid:"model", endpointid:"model", speaker:"speaker", speakerid:"speaker"}));
  const result = {}, seen = new Set(); let shared;
  for (const [name, raw] of entries) {
    const key = name.toLowerCase().replace(/[\s_-]/g, "");
    if (seen.has(key)) throw new Error(); seen.add(key);
    if (key === "apikeyid") continue; // Administrative ID is not a speech App ID.
    const target = aliases.get(key);
    if (!target && key !== "apikeysecret") continue;
    if (typeof raw !== "string") throw new Error();
    let value = raw.trim();
    if ((value.startsWith('"') && value.endsWith('"')) || (value.startsWith("'") && value.endsWith("'"))) value = value.slice(1, -1);
    if (!/^[\x21-\x7e]{1,512}$/.test(value)) throw new Error();
    if (key === "apikeysecret") shared = value;
    else { if (result[target]) throw new Error(); result[target] = value; }
  }
  // A generic IAM Secret is not proven to be a Speech console API Key.
  if (shared) result.arkKey ||= shared;
  if (!Object.keys(result).length) throw new Error();
  return result;
}
$("configFile").onchange = async () => {
  const file = $("configFile").files?.[0]; if (!file || connected || connecting) return;
  const generation = ++importGeneration; configRevision++; importing = true; controls();
  try {
    if (file.size > 65536) throw new Error();
    const values = parseCredentialFile(await file.text());
    if (generation !== importGeneration) return;
    for (const [id, value] of Object.entries(values)) $(id).value = value;
    const missing = [["model", "豆包文本模型 ID"], ["speaker", "粤语音色 ID"]].filter(([id]) => !$(id).value.trim()).map(([, label]) => label);
    if (!$("speechKey").value && !($("appId").value && $("accessKey").value)) missing.push("语音凭证");
    if (!$("arkKey").value) missing.push("方舟凭证");
    const message = `本地配置已导入；尚未验证云端权限。${missing.length ? "还需填写：" + missing.join("、") + "。" : "可开始连接测试。"}`;
    $("importStatus").textContent = message; status(message);
  } catch { if (generation === importGeneration) { $("importStatus").textContent = "导入失败：请检查文件格式（64 KB 以内，字段名: 值或 JSON）。未更改现有配置。"; status("配置文件未导入。", true); } }
  finally { $("configFile").value = ""; importing = false; controls(); }
};
$("saveConfig").onclick = async () => {
  try {
    const values = config();
    const r = await fetch("/windows/config", {method:"POST", headers:{Authorization:`Bearer ${token}`, "Content-Type":"application/json"}, body:JSON.stringify(values)});
    if (!r.ok) throw new Error();
    status("配置已保存到本机服务。刷新或换浏览器会自动填入；关闭本机服务后清空。");
    $("importStatus").textContent = "本机服务已临时保存配置，密钥未写入文件。";
  } catch { status("配置未保存，请检查各项填写是否完整及本机服务是否连接。", true); }
};
$("clear").onclick = async () => {
  importGeneration++; configRevision++;
  for (const id of ["speechKey", "accessKey", "arkKey"]) $(id).value = "";
  $("importStatus").textContent = "本页凭证已清空。";
  try {
    const r = await fetch("/windows/config", {method:"DELETE", headers:{Authorization:`Bearer ${token}`}});
    if (!r.ok) throw new Error();
    status("本页凭证及本机保存的配置已清空；其他已打开页面如需清空，请刷新。");
  } catch { status("本页已清空，但本机保存的配置未能删除，请重试清空或关闭本机服务。", true); }
};
$("settingsToggle").onclick = () => { $("settings").hidden = !$("settings").hidden; $("settingsToggle").textContent = $("settings").hidden ? "展开 API 配置" : "收起 API 配置"; };
$("policyTest").onclick = async () => {
  $("policyTest").disabled = true; $("policyResults").replaceChildren();
  try {
    for (const text of ["我应该食乜药？", "买边只股票好？", "讲一下政治", "我想约陈伯散步", "救命，我透唔到气"]) {
      const r = await fetch("/windows/policy-check", {method: "POST", headers: {Authorization: `Bearer ${token}`, "Content-Type": "application/json"}, body: JSON.stringify({text})});
      if (!r.ok) throw new Error(); const result = await r.json(), p = document.createElement("p"); p.textContent = `${text} → ${result.label}`; $("policyResults").append(p);
    }
    status("本地规则检查完成；没有调用豆包，不代表真实模型或语音效果。");
  } catch { status("规则检查失败，请确认本机服务已更新并启动。", true); }
  finally { controls(); }
};
window.addEventListener("pagehide", () => { mic?.getTracks().forEach(t => t.stop()); ws?.close(); for (const id of ["speechKey", "accessKey", "arkKey"]) $(id).value = ""; });
document.addEventListener("visibilitychange", () => { if (document.hidden && (connected || micOnly || connecting)) { status("页面进入后台，已停止收音；返回后请重新连接。"); disconnect(); } });
(async () => {
  const revision = configRevision;
  try {
    const r = await fetch("/windows/session"); if (!r.ok) throw new Error(); token = (await r.json()).token;
    const response = await fetch("/windows/config", {headers:{Authorization:`Bearer ${token}`}}); if (!response.ok) throw new Error();
    const saved = (await response.json()).config;
    if (configRevision === revision && saved) {
      const mapping = {speech_key:"speechKey",app_id:"appId",access_key:"accessKey",ark_key:"arkKey",model:"model",speaker:"speaker",tts_resource:"ttsResource",asr_resource:"asrResource",end_window_ms:"pauseMs",speech_rate:"rate"};
      for (const [key,id] of Object.entries(mapping)) if (saved[key] !== undefined) $(id).value = String(saved[key]);
      $("importStatus").textContent = "已自动载入本机服务保存的配置。";
      status("配置已自动填好，直接点击开始粤语对话即可。");
      $("settings").hidden = true; $("settingsToggle").textContent = "展开 API 配置";
    } else if (configRevision === revision) status("本机服务已就绪。请填写或导入配置，再保存到本机服务。");
  } catch { status("无法读取本机配置，请确认服务已更新并运行。", true); }
  controls();
})();
