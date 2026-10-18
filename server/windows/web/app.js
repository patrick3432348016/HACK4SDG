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
  $("connection").textContent = connected ? "Doubao connected" : connecting ? "Connecting" : micOnly ? "Local microphone check" : "Awaiting configuration";
  $("connection").classList.toggle("online", connected);
  $("orb").classList.toggle("active", connected || micOnly);
}
function config() {
  const value = {speech_key: $("speechKey").value.trim(), app_id: $("appId").value.trim(), access_key: $("accessKey").value.trim(),
    ark_key: $("arkKey").value.trim(), model: $("model").value.trim(), speaker: $("speaker").value.trim(),
    asr_resource: $("asrResource").value, tts_resource: $("ttsResource").value,
    end_window_ms: Number($("pauseMs").value), speech_rate: Number($("rate").value)};
  if ((!value.speech_key && !(value.app_id && value.access_key)) || !value.ark_key || !value.model || !value.speaker)
    throw new Error("Enter Speech credentials, an Ark API key, a Doubao model ID, and a Cantonese-capable voice ID first.");
  return value;
}
function configurationEdited() {
  configRevision++;
  if (connecting || connected) return;
  $("importStatus").textContent = "Configuration changed. Save to the local service to restore it after refreshing or switching browsers.";
  try { config(); status("Configuration entered; not connected. Start a Cantonese conversation to open the microphone and connect to Doubao."); }
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
  phase("Continue speaking", "The previous reply has stopped. Listening for your next sentence."); controls();
}
async function microphone(local, generation) {
  if (!navigator.mediaDevices?.getUserMedia || !window.AudioWorkletNode) throw new Error("This browser does not support live audio capture. Open the local URL in Windows Edge or Chrome.");
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
    if (ws.bufferedAmount > 128000) { status("Network backlog detected. Disconnected to avoid playing stale replies.", true); disconnect(); return; }
    // Volume alone cannot distinguish speech from noise. The backend interrupts
    // on a new ASR partial; acoustic onsets must not cancel a pending answer.
    ws.send(data.pcm);
  };
  mic.getAudioTracks()[0].onended = () => { status("The microphone was disconnected.", true); disconnect(); };
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
  $("level").value = 0; $("partial").textContent = "Audio capture stopped";
  phase("Conversation ended", "Audio capture is off. Reconnect when needed."); shuttingDown = false; controls();
}
function bubble(who, text) {
  const chat = $("chat"); chat.querySelector(".empty")?.remove();
  const node = document.createElement("div"); node.className = `bubble ${who}`;
  const label = document.createElement("small"); label.textContent = who === "user" ? "You" : "StreetWalk assistant · concise app reply";
  node.append(label, document.createTextNode(text)); chat.append(node);
  while (chat.children.length > 40) chat.firstElementChild.remove(); chat.scrollTop = chat.scrollHeight;
}
function renderBusiness(data) {
  $("choices").replaceChildren(); $("businessEmpty").hidden = Boolean(data);
  $("business").textContent = data?.message || ""; $("businessJson").textContent = data ? JSON.stringify(data, null, 2) : "No request yet";
  if (!data) return;
  const action = (label, params) => {
    const b = document.createElement("button"); b.className = "secondary"; b.textContent = label;
    b.onclick = () => { if (!connected || responsePending) return; responsePending = true; controls(); ws.send(JSON.stringify({type: "action", ...params})); };
    $("choices").append(b);
  };
  for (const choice of data.choices || []) action(`${choice.label}${choice.detail ? " · " + choice.detail : ""}`, {kind: "choice", choice_kind: data.status === "choose_contact" ? "contact" : "place", value: choice.id});
  if (data.status === "needs_confirmation") { action("Check and confirm test action", {kind: "confirm"}); action("Cancel", {kind: "cancel"}); }
  controls();
}
function renderWeather(data) {
  if (!data) return;
  const card = $("weather"); card.replaceChildren();
  const line = (text, muted = false) => { const p = document.createElement("p"); p.textContent = text; if (muted) p.className = "muted"; card.append(p); };
  const at = value => new Date(value).toLocaleString("en-GB", {timeZone: "Asia/Hong_Kong", hour12: false});
  line(`${data.requested_place} · Request date ${data.date}`);
  for (const item of data.observations || []) line(`${item.station} station: ${item.temperature_c}°C · ${at(item.recorded_at)}`);
  if (data.rainfall) line(`North District maximum recorded rainfall: ${data.rainfall.max_mm} mm (${at(data.rainfall.from)} to ${at(data.rainfall.to)}); past rainfall does not predict whether it will rain later.`, true);
  if (data.forecast) {
    line(`Hong Kong-wide forecast reference · ${data.forecast.period}`);
    line(data.forecast.description);
    if (data.forecast.min_c !== undefined) line(`Hong Kong-wide forecast temperature ${data.forecast.min_c}–${data.forecast.max_c}°C`);
    line(`Forecast issued: ${at(data.forecast.updated_at)}`, true);
  }
  line(data.warnings?.length ? `Current warnings: ${data.warnings.map(w => w.name).join(", ")}` : data.warnings_available ? "No active warnings were listed in the retrieved summary; travel may still carry risks." : "Could not verify the latest weather warnings.");
  for (const note of data.notes || []) line(note, true);
  line(`Checked at (Hong Kong): ${at(data.checked_at)}`, true);
}
function play(message) {
  if (!context || message.turn_id !== turn || message.turn_id <= blockedTurn) return;
  const raw = atob(message.data), bytes = Uint8Array.from(raw, c => c.charCodeAt(0));
  if (bytes.length % 2 || message.sample_rate !== 24000) throw new Error("Invalid speech audio received.");
  const view = new DataView(bytes.buffer), buffer = context.createBuffer(1, bytes.length/2, 24000), channel = buffer.getChannelData(0);
  for (let i=0; i<channel.length; i++) channel[i] = view.getInt16(i*2, true)/32768;
  nextPlay = Math.max(context.currentTime + .04, nextPlay);
  if (nextPlay - context.currentTime > 50) throw new Error("Speech queue too long; playback stopped.");
  const source = context.createBufferSource(); source.buffer = buffer; source.connect(context.destination); sources.add(source);
  source.onended = () => { sources.delete(source); if (!sources.size) { $("orb").classList.remove("speaking"); if (!responsePending && connected) phase("Listening", "You can continue asking about the app."); } };
  source.start(nextPlay); nextPlay += buffer.duration; $("orb").classList.add("speaking"); phase("Replying in Cantonese", "Speak to interrupt, or click Interrupt speech.");
  if (firstAudio) { firstAudio = false; $("metrics").textContent = `Final transcript to first audio: ${((performance.now()-transcriptAt)/1000).toFixed(2)} s (excludes earlier recognition and end-of-speech detection)`; }
}
function event(message) {
  if (message.type === "ready") {
    connecting = false; connected = true; status("Doubao recognition connected. Speak Cantonese; a reply follows after a sentence-end pause."); phase("Listening", "Continuous capture is on. Pause after a sentence to receive a reply."); controls(); return;
  }
  if (message.type === "error") { status(`${message.message} [${message.code}]`, true); disconnect(); return; }
  if (message.type === "transcript") {
    $("partial").textContent = message.text;
    if (message.final) { bubble("user", message.text); transcriptAt = performance.now(); renderBusiness(null); }
    return;
  }
  if (message.type === "interrupted") { turn = message.turn_id; stopAudio(); responsePending = false; controls(); return; }
  if (message.turn_id !== turn || message.turn_id <= blockedTurn) return;
  if (message.type === "thinking") { responsePending = true; firstAudio = true; phase("Preparing a reply", "Your speech was received. A Cantonese reply will follow shortly."); status("Recognition complete; generating an app-related reply..."); controls(); }
  if (message.type === "answer") { bubble("assistant", message.text); renderBusiness(message.business); renderWeather(message.weather); status(message.policy === "deny" ? "Reply limited to the supported scope; unrelated topics were not expanded." : "Reply ready; waiting for Cantonese audio."); }
  if (message.type === "audio") play(message);
  if (message.type === "answer_done") { responsePending = false; if (!sources.size) phase("Listening"); controls(); }
  if (message.type === "turn_error") { stopAudio(); responsePending = false; status(`${message.message} [${message.code}]`, true); phase("This reply did not complete", "Continue speaking, or check the API configuration and reconnect."); controls(); }
}
$("connect").onclick = async () => {
  if (connecting || connected) return;
  let generation;
  try {
    const settings = config(); generation = ++lifecycle; connecting = true; turn = -1; blockedTurn = -1; controls(); renderBusiness(null);
    status("Waiting for microphone permission and connecting to Doubao..."); if (!await microphone(false, generation)) return;
    if (!connecting || generation !== lifecycle) return;
    ws = new WebSocket(`${location.protocol === "https:" ? "wss:" : "ws:"}//${location.host}/windows/realtime`);
    const current = ws;
    ws.onopen = () => current.send(JSON.stringify({token, config: settings}));
    ws.onmessage = e => { if (current !== ws) return; try { event(JSON.parse(e.data)); } catch { status("Message handling failed; this conversation has stopped.", true); disconnect(); } };
    ws.onerror = () => { if (current === ws) status("Live connection failed. Check that the local service is running.", true); };
    ws.onclose = () => { if (current === ws) { if (!$("status").classList.contains("error")) status("Live connection closed. Start the conversation again."); disconnect(); } };
  } catch (error) {
    if (generation === undefined) { status(error.message, true); controls(); return; }
    if (generation !== undefined && generation !== lifecycle) return;
    const permissions = {NotAllowedError: "Microphone permission denied. Allow access in browser site permissions and Windows privacy settings.", NotFoundError: "No microphone detected.", NotReadableError: "Microphone unavailable. Check the device and whether another application is using it."};
    status(permissions[error.name] || error.message, true); await disconnect();
  }
};
$("micTest").onclick = async () => { const generation = ++lifecycle; micOnly = true; controls(); try { if (!await microphone(true, generation)) return; phase("Checking microphone", "Speak and watch the level meter. Audio is neither uploaded nor recognized during this check."); status("This is a local device check. Click End conversation to close the microphone."); } catch { if (generation !== lifecycle) return; status("Could not open the microphone. Check browser and Windows recording permissions.", true); await disconnect(); } };
$("stop").onclick = () => { status("Conversation ended by the user."); disconnect(); };
$("interrupt").onclick = interrupt;
$("typed").oninput = controls;
$("send").onclick = () => { const text = $("typed").value.trim(); if (!connected || !text) return; interrupt(); ws.send(JSON.stringify({type: "text", text})); $("typed").value = ""; controls(); };
$("typed").onkeydown = e => { if (e.key === "Enter" && !e.isComposing && !$("send").disabled) $("send").click(); };
function parseCredentialFile(text) {
  if (typeof text !== "string" || text.length > 65536) throw new Error("File too large. Select a configuration file no larger than 64 KB.");
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
    const missing = [["model", "Doubao text model ID"], ["speaker", "Cantonese voice ID"]].filter(([id]) => !$(id).value.trim()).map(([, label]) => label);
    if (!$("speechKey").value && !($("appId").value && $("accessKey").value)) missing.push("Speech credentials");
    if (!$("arkKey").value) missing.push("Ark credentials");
    const message = `Local configuration imported; cloud permissions have not been verified. ${missing.length ? "Still required: " + missing.join(", ") + "." : "Ready for a connection test."}`;
    $("importStatus").textContent = message; status(message);
  } catch { if (generation === importGeneration) { $("importStatus").textContent = "Import failed. Check the format (up to 64 KB; field: value or JSON). Existing configuration is unchanged."; status("Configuration file was not imported.", true); } }
  finally { $("configFile").value = ""; importing = false; controls(); }
};
$("saveConfig").onclick = async () => {
  try {
    const values = config();
    const r = await fetch("/windows/config", {method:"POST", headers:{Authorization:`Bearer ${token}`, "Content-Type":"application/json"}, body:JSON.stringify(values)});
    if (!r.ok) throw new Error();
    status("Configuration saved in the local service. It restores after refreshing or switching browsers and clears when the service stops.");
    $("importStatus").textContent = "Configuration is temporarily held by the local service; keys were not written to a file.";
  } catch { status("Configuration not saved. Check the required fields and the local service connection.", true); }
};
$("clear").onclick = async () => {
  importGeneration++; configRevision++;
  for (const id of ["speechKey", "accessKey", "arkKey"]) $(id).value = "";
  $("importStatus").textContent = "Credentials cleared from this page.";
  try {
    const r = await fetch("/windows/config", {method:"DELETE", headers:{Authorization:`Bearer ${token}`}});
    if (!r.ok) throw new Error();
    status("Page credentials and locally saved configuration cleared. Refresh other open pages to clear them too.");
  } catch { status("This page is cleared, but saved local configuration could not be removed. Retry Clear or stop the local service.", true); }
};
$("settingsToggle").onclick = () => { $("settings").hidden = !$("settings").hidden; $("settingsToggle").textContent = $("settings").hidden ? "Show API configuration" : "Hide API configuration"; };
$("policyTest").onclick = async () => {
  $("policyTest").disabled = true; $("policyResults").replaceChildren();
  try {
    for (const text of ["我应该食乜药？", "买边只股票好？", "讲一下政治", "我想约陈伯散步", "救命，我透唔到气"]) {
      const r = await fetch("/windows/policy-check", {method: "POST", headers: {Authorization: `Bearer ${token}`, "Content-Type": "application/json"}, body: JSON.stringify({text})});
      if (!r.ok) throw new Error(); const result = await r.json(), p = document.createElement("p"); p.textContent = `${text} → ${result.label}`; $("policyResults").append(p);
    }
    status("Local rule check complete. Doubao was not called; this does not measure live model or speech performance.");
  } catch { status("Rule check failed. Check that the local service is up to date and running.", true); }
  finally { controls(); }
};
window.addEventListener("pagehide", () => { mic?.getTracks().forEach(t => t.stop()); ws?.close(); for (const id of ["speechKey", "accessKey", "arkKey"]) $(id).value = ""; });
document.addEventListener("visibilitychange", () => { if (document.hidden && (connected || micOnly || connecting)) { status("Page moved to the background; capture stopped. Reconnect when you return."); disconnect(); } });
(async () => {
  const revision = configRevision;
  try {
    const r = await fetch("/windows/session"); if (!r.ok) throw new Error(); token = (await r.json()).token;
    const response = await fetch("/windows/config", {headers:{Authorization:`Bearer ${token}`}}); if (!response.ok) throw new Error();
    const saved = (await response.json()).config;
    if (configRevision === revision && saved) {
      const mapping = {speech_key:"speechKey",app_id:"appId",access_key:"accessKey",ark_key:"arkKey",model:"model",speaker:"speaker",tts_resource:"ttsResource",asr_resource:"asrResource",end_window_ms:"pauseMs",speech_rate:"rate"};
      for (const [key,id] of Object.entries(mapping)) if (saved[key] !== undefined) $(id).value = String(saved[key]);
      $("importStatus").textContent = "Loaded configuration saved by the local service.";
      status("Configuration restored. Click Start Cantonese conversation.");
      $("settings").hidden = true; $("settingsToggle").textContent = "Show API configuration";
    } else if (configRevision === revision) status("Local service ready. Enter or import configuration, then save it to the local service.");
  } catch { status("Could not read local configuration. Check that the service is up to date and running.", true); }
  controls();
})();
