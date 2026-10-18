// Headless state tests with synthetic browser primitives, not microphone verification.
const fs = require('node:fs'), vm = require('node:vm'), assert = require('node:assert/strict'), path = require('node:path');
const script = fs.readFileSync(path.join(__dirname, '../windows/web/app.js'), 'utf8');
function harness(deferred = false) {
  const elements = new Map(), sockets = [], tracks = [], players = [], worklets = []; let permission;
  const element = () => ({value:'', textContent:'', hidden:false, disabled:false, children:[], scrollHeight:0,
    classList:{toggle(){},add(){},remove(){},contains(){return false;}}, append(...x){this.children.push(...x);}, replaceChildren(){this.children=[];}, querySelector(){return null;}, querySelectorAll(){return [];}, remove(){}});
  const document = {hidden:false, getElementById(id){if(!elements.has(id)) elements.set(id,element());return elements.get(id);},createElement:element,createTextNode:t=>t,addEventListener(){}};
  function stream(){const t={stopped:false,stop(){this.stopped=true;}}; tracks.push(t); return {getTracks:()=>[t],getAudioTracks:()=>[t]};}
  class WS { static OPEN=1; constructor(){this.readyState=1;this.bufferedAmount=0;this.sent=[];sockets.push(this);} send(v){this.sent.push(v);}close(){this.readyState=3;} }
  class Context {constructor(){this.state='running';this.currentTime=0;this.audioWorklet={addModule:async()=>{}};this.destination={};}async resume(){} async close(){this.state='closed';}createGain(){return {gain:{},connect(){}};}createMediaStreamSource(){return {connect(){}};}createBuffer(c,n,r){return {duration:n/r,getChannelData:()=>new Float32Array(n)};}createBufferSource(){const p={connect(){},start(){this.started=true;},stop(){this.stopped=true;}};players.push(p);return p;}}
  class Worklet {constructor(){this.port={};worklets.push(this);}connect(){return {connect(){}};}disconnect(){}}
  const sandbox = {document, navigator:{mediaDevices:{getUserMedia:()=>deferred?new Promise(r=>permission=()=>r(stream())):Promise.resolve(stream())}},
    window:{AudioWorkletNode:Worklet,addEventListener(){}},AudioWorkletNode:Worklet,AudioContext:Context,WebSocket:WS,
    location:{protocol:'http:',host:'127.0.0.1:8765'},fetch:async()=>({ok:true,json:async()=>({token:'fake-local-token'})}),
    performance:{now:()=>100},atob:s=>Buffer.from(s,'base64').toString('binary'),Uint8Array,DataView,Float32Array,Set,console};
  vm.runInNewContext(script,sandbox);
  const get=id=>document.getElementById(id);
  for(const [id,value] of Object.entries({speechKey:'test',arkKey:'test',model:'test-model',speaker:'test-speaker',asrResource:'volc.seedasr.sauc.duration',ttsResource:'seed-tts-2.0',pauseMs:'1200',rate:'-15'})) get(id).value=value;
  return {get,sockets,tracks,players,worklets,grant:()=>permission(),event:m=>sockets.at(-1).onmessage({data:JSON.stringify(m)})};
}
(async()=>{
  const imported=harness();await new Promise(setImmediate);
  imported.get('arkKey').value=''; imported.get('speechKey').value=''; imported.get('appId').value='';
  imported.get('configFile').files=[{size:100,text:async()=> 'API Key ID: administrative-id\nAPI Key Secret: synthetic-secret'}];
  await imported.get('configFile').onchange();
  assert.equal(imported.get('speechKey').value,'','Generic IAM Secret must not silently become a Speech key');
  assert.equal(imported.get('arkKey').value,'synthetic-secret');
  assert.equal(imported.get('appId').value,'','Key ID must never become App ID');
  assert.ok(!imported.get('status').textContent.includes('synthetic-secret'));
  imported.get('configFile').files=[{size:100,text:async()=> 'speech_key: changed\nark_key: invalid secret'}];
  await imported.get('configFile').onchange();
  assert.equal(imported.get('speechKey').value,'','invalid file must be atomic');
  let finishImport; imported.get('configFile').files=[{size:100,text:()=>new Promise(r=>finishImport=r)}];
  const importing=imported.get('configFile').onchange(); imported.get('clear').onclick(); finishImport('API Key Secret: synthetic-secret');await importing;
  assert.equal(imported.get('arkKey').value,'','Clear must cancel in-flight import');
  const h=harness();await new Promise(setImmediate);await h.get('connect').onclick();h.sockets[0].onopen();h.event({type:'ready'});
  h.event({type:'interrupted',turn_id:1});h.event({type:'thinking',turn_id:1});
  const sentBeforeNoise=h.sockets[0].sent.length;
  h.worklets[0].port.onmessage({data:{onset:true,rms:.1,pcm:new ArrayBuffer(6400)}});
  assert.equal(h.sockets[0].sent.length,sentBeforeNoise+1);
  assert.ok(h.sockets[0].sent.at(-1) instanceof ArrayBuffer,'noise must stream PCM without cancelling the waiting reply');
  h.event({type:'answer',turn_id:1,text:'天气测试',policy:'weather',weather:{requested_place:'北區',date:'2026-10-13',checked_at:'2026-10-12T12:00:00+08:00',observations:[],warnings:[],warnings_available:false,notes:[],forecast:{period:'2026-10-13',description:'有雨。',min_c:24,max_c:29,updated_at:'2026-10-12T11:00:00+08:00'}}});
  const weatherText=h.get('weather').children.map(p=>p.textContent).join('\n');
  assert.ok(weatherText.includes('Hong Kong-wide forecast reference'));
  assert.ok(weatherText.includes('Could not verify the latest weather warnings'));
  assert.ok(weatherText.includes('2026-10-13'));
  assert.ok(!weatherText.includes('no risk'));
  const audio={type:'audio',turn_id:1,sample_rate:24000,data:Buffer.alloc(480).toString('base64')};
  h.event(audio);assert.equal(h.players.length,1);h.get('interrupt').onclick();assert.equal(h.players[0].stopped,true);
  h.event(audio);assert.equal(h.players.length,1,'late audio must not restart after interruption');
  h.event({type:'interrupted',turn_id:2});h.event({...audio,turn_id:2});assert.equal(h.players.length,2);
  h.get('stop').onclick();await new Promise(setImmediate);assert.equal(h.tracks[0].stopped,true);
  assert.equal(h.sockets[0].readyState,3);
  const d=harness(true);await new Promise(setImmediate);const pending=d.get('connect').onclick();d.get('stop').onclick();d.grant();await pending;
  assert.equal(d.tracks[0].stopped,true,'permission arriving after Stop must release microphone');
  assert.equal(d.sockets.length,0,'cancelled permission request must not open cloud session');
  const m=harness();await new Promise(setImmediate);await m.get('micTest').onclick();assert.equal(m.sockets.length,0,'local mic check must not connect to cloud');m.get('stop').onclick();await new Promise(setImmediate);
  assert.equal(m.tracks[0].stopped,true);
  console.log('UI state tests passed: weather scope/date/warning availability, credential import, atomic validation, clear race, late audio, interruption, stop, permission race, local mic isolation.');
})().catch(e=>{console.error(e);process.exitCode=1;});
