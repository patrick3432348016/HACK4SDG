# StreetWalk Speech Research: Cantonese, Mandarin and English Voices

**Research date: 2026-10-09. Historical research, not current provider advice.** Prices, model names, availability, rankings and terms below reproduce the dated research record and have not been revalidated in this translation. Current StreetWalk uses the [integrated Doubao service](../../server/README.md); the earlier recommendation to prerecord a local demo was superseded by implementation work. Do not use this page as proof of present pricing, compliance or voice quality.

Evidence labels: **Official** means vendor documentation/catalogs; **Community** means media, forums or third-party rankings; **Measured** means the team's iOS 26.4/26.5 simulator or Mac checks, **not an iPhone 11 test**; **Inference** lacks direct validation; **Uncertain** marks unresolved or corrected claims.

## 1. Findings and the recommendation at the time

The code then selected `AVSpeechSynthesisVoice(language: "zh-HK")`, which returned the basic super-compact Sinji voice in the tested simulator, a roughly 3.2 MB package. Apple describes the default tier as basic quality. The inference that low tier caused the perceived stiffness had not been tested against premium voices on an actual phone. iOS does not offer Android-style third-party system voice packs; Apple downloads, custom audio playback and separately integrated models are different options.

There was **no established Cantonese naturalness ranking** in the reviewed material. The dated note found no Cantonese category among Artificial Analysis's ten language boards, an English-only TTS Arena, and zero synthesis entries in a Cyberport/Prudential Cantonese benchmark; the last observation was not independently rechecked. Cantonese candidates therefore required blind listening with actual App sentences, not a claim of being objectively best.

Candidate shortlist then:

- Cantonese: Google Chirp 3 HD and MiniMax; Apple premium Sinji, Wing and Fung for account-free local use. Cantonese premium Apple quality had no located listening evaluation.
- Mandarin: the note cited a secondary Inworld ranking and a 2025 study favoring Doubao Seed-TTS / MiniMax for human likeness. Operationally, sharing a provider with Cantonese was proposed. Local candidates included Lilian, Yue, Yun and Han.
- English: the dated English leaderboard favored ElevenLabs v4/Turbo; local candidates were Ava, Serena and Malcolm.

The proposed sequence was: first implement local controls, language-aware best-voice selection, download guidance and three speeds; then blind-test and prerecord demo sentences, with system fallback; defer real-time cloud or local-model integration. Prerecording would remove runtime keys/network delay, use only fictional demo text and avoid the reported Mandarin-to-Cantonese system bug. It would cover only known lines; new model-generated sentences would still need fallback.

## 2. Dated comparison

All figures in this table are **claims recorded on the research date**, subject to the corrections below and fresh verification before selection or spending. English ranking scores do not measure Cantonese.

| Option | Languages/voices recorded | Evidence and limitations | Deployment, cost and data handling recorded |
|---|---|---|---|
| Apple basic | Sinji Cantonese, Tingting Mandarin, Samantha US English | Official basic tier; community descriptions called defaults robotic | Local/offline, no account, free; already integrated |
| Apple enhanced/premium | Sinji, Wing, Fung, enhanced Aasing; Mandarin Lilian/Lili/Yue/Yun/Han; English Ava/Zoe/Serena/Malcolm | No located Cantonese quality review; conflicting community Chinese-voice opinions; Ava recommended by CoMaps | User downloads, roughly 10–47 MB for Cantonese, free/local; low integration effort |
| Google Chirp 3 HD | Thirty named voices for yue-HK, cmn-CN and en-US; Cantonese listed as preview | No independent Cantonese blind test; recorded English score 1059 | Cloud account/billing; first 1M characters monthly free, then $30/M in the dated note; vendor stated no text/audio logging |
| MiniMax Speech 2.8 | Six-plus Cantonese voices including KindWoman/GentleLady; many Mandarin/English voices | Positive PCM review, not blind testing; English score 1174; second in a cited 2025 Mandarin human-likeness test | Cloud key; recorded Turbo $60/M, HD $100/M, with uncertain double-counting of Chinese characters; terms allowed service improvement and US storage; Jyutping pronunciation control |
| ElevenLabs v4/v4 Turbo | Cantonese listed from 2026-09-28, Mandarin/English; no preset Cantonese voice noted | English scores 1326/1329 statistically tied; no independent Cantonese evaluation | Recorded $80/M or $40/M; Starter $6/month; paid plan for commercial use; default retention; speed tags rather than a slider in that record |
| Azure neural | Cantonese HiuGaai/HiuMaan/WanLung; many Mandarin/English HD voices | Paper's Edge-TTS Cantonese accent score 3.48/5; attribution to Azure and mechanicalness were inferences, corrected below | Cloud, Hong Kong region option; recorded $15/M and free 0.5M/month at 20 requests/minute; vendor stated no real-time text/audio storage |
| Qwen3-TTS-Flash | Cantonese Kiki/Rocky, Mandarin and English | Singapore availability inferred from documentation; no Cantonese evaluation found | Recorded roughly $10/M; Singapore region; retention unresolved |
| Amazon Polly | Cantonese Hiujin, Mandarin Zhiyu, many English voices | Recorded English neural score 895; no Cantonese evaluation | Recorded $16/M and first-year 1M/month free; caching explicitly allowed; service-improvement use with opt-out |
| sherpa-onnx Cantonese model | One 2023 community voice; other models could supply Mandarin/English | No evaluation or located model license; sentence-ending issue fixed in 2025 | Local/offline, roughly 114 MB; licensing unresolved; medium/high integration effort |
| Kokoro-82M | No Cantonese; Mandarin v1 voices self-rated D; English af_heart self-rated A | Recorded English score 1065; no iPhone 11 speed result | Local roughly 80–170 MB, Apache-2.0; medium effort |
| CosyVoice2-Yue / VoxCPM2 | Cantonese claimed, plus Mandarin/English | CosyVoice author evaluation: intelligibility 4.45, accent 4.21; no VoxCPM2 Cantonese test found | Server/computer inference proposed, high effort; CosyVoice training data restricted to noncommercial use |

Sources from the original research, retained for traceability:

- Apple: [voice quality](https://developer.apple.com/documentation/avfaudio/avspeechsynthesisvoicequality), [official asset catalog](https://mesu.apple.com/assets/com_apple_MobileAsset_TTSAXResourceModelAssets/com_apple_MobileAsset_TTSAXResourceModelAssets.xml), [CoMaps discussion](https://www.comaps.app/news/ios-hq-voices/), [AppleVis discussion](https://mail.applevis.com/forum/ios-ipados/ios-chinese-tts-voice-quality-very-poor).
- Google: [Chirp documentation](https://docs.cloud.google.com/text-to-speech/docs/chirp3-hd), [voice list](https://docs.cloud.google.com/text-to-speech/docs/list-voices-and-types), [pricing](https://cloud.google.com/text-to-speech/pricing), [logging](https://docs.cloud.google.com/text-to-speech/docs/data-logging), [preview terms](https://cloud.google.com/terms/service-terms).
- MiniMax: [PCM review](https://www.pcmarket.com.hk/minimax-free-cantonese-ai-voice-actor/), [voices](https://platform.minimax.io/docs/faq/system-voice-id), [pricing](https://platform.minimax.io/docs/guides/pricing-paygo.md), [terms](https://platform.minimax.io/docs/guides/terms-of-service.md), [privacy](https://platform.minimax.io/docs/guides/privacy-policy.md), [Mandarin study](https://arxiv.org/html/2505.11200v1).
- ElevenLabs: [models](https://elevenlabs.io/docs/overview/models), [v4 capabilities](https://elevenlabs.io/docs/overview/capabilities/text-to-speech/eleven-v4), [pricing](https://elevenlabs.io/pricing/api), [retention](https://elevenlabs.io/docs/resources/zero-retention-mode), [billing restrictions](https://elevenlabs.io/docs/overview/administration/billing), [audio tags](https://elevenlabs.io/blog/elevenlabs-audio-tags-list).
- Azure: [languages](https://learn.microsoft.com/en-us/azure/ai-services/speech-service/language-support?tabs=tts), [privacy](https://learn.microsoft.com/en-us/azure/ai-foundry/responsible-ai/speech-service/text-to-speech/data-privacy-security), [quotas](https://learn.microsoft.com/en-us/azure/ai-services/speech-service/speech-services-quotas-and-limits), [HD voices](https://learn.microsoft.com/en-us/azure/ai-services/speech-service/high-definition-voices), [WenetSpeech-Yue paper](https://arxiv.org/html/2509.03959v2).
- Alibaba: [voices](https://www.alibabacloud.com/help/en/model-studio/qwen-tts-voice-list), [regions](https://www.alibabacloud.com/help/en/model-studio/qwen-tts).
- Amazon: [voices](https://docs.aws.amazon.com/polly/latest/dg/available-voices.html), [FAQ](https://aws.amazon.com/polly/faqs/), [pricing](https://aws.amazon.com/polly/pricing/).
- Open models: [sherpa-onnx](https://github.com/k2-fsa/sherpa-onnx), [Cantonese model](https://huggingface.co/csukuangfj/vits-cantonese-hf-xiaomaiiwn), [fix PR 2558](https://github.com/k2-fsa/sherpa-onnx/pull/2558), [Kokoro voice ratings](https://huggingface.co/hexgrad/Kokoro-82M/blob/main/VOICES.md), [third-party Core ML timing](https://huggingface.co/mattmireles/kokoro-coreml), [CosyVoice2-Yue](https://huggingface.co/ASLP-lab/Cosyvoice2-Yue), [training-data license](https://huggingface.co/datasets/ASLP-lab/WenetSpeech-Yue), [VoxCPM2](https://huggingface.co/openbmb/VoxCPM2).
- Benchmarks: [Artificial Analysis](https://artificialanalysis.ai/text-to-speech/leaderboard), [Cantonese challenge](https://ai-challenge.pubrio.com/).

### Options excluded in that research

- Siri: [WWDC20](https://developer.apple.com/videos/play/wwdc2020/10022/) said third-party AVSpeechSynthesizer could not use Siri voices; the research found no later opening of that API.
- Personal Voice: the dated [availability](https://www.apple.com/ios/feature-availability/#accessibility-personal-voice) and [support](https://support.apple.com/en-us/104993) references limited devices/languages; iPhone 12 or later was cited. A user's recorded personal voice was also a poor fit for a generic narrator.
- OpenAI: the research cited missing Cantonese in the [TTS list](https://developers.openai.com/api/docs/guides/text-to-speech) and Hong Kong absence from [supported countries](https://developers.openai.com/api/docs/supported-countries). These dated availability conclusions require rechecking.
- Gemini TTS: the dated [region list](https://ai.google.dev/gemini-api/docs/available-regions) did not list Hong Kong.
- BytePlus/iFlytek: only one Cantonese voice located, no evaluation and uncertain Hong Kong signup.
- Inworld/Cartesia: Mandarin rankings did not establish Cantonese support or quality.

## 3. Accessibility and privacy considerations

The then-current rate was 0.42 versus system default 0.5. Simulator readings of the same Cantonese outing sentence took 4.25 seconds at 0.5, 4.68 at 0.4 and 5.53 at 0.3. The initial proposal was three speeds with a slower default, to be decided by resident listening tests; current tuning has since changed.

The research proposed pauses, matching on-screen text and a large Replay action. Test colloquial Cantonese characters, numbers, times and mixed-language names. MiniMax documented Jyutping correction; the dated Chirp Cantonese interface supported speed but not explicit pause or pronunciation controls, so punctuation and rewritten numerals were proposed. The early suggestion to split at commas was later superseded in code by sentence-level utterances for continuity.

Keep other-audio ducking and test real volume. A [2022 AppleVis report](https://mail.applevis.com/comment/142091) concerned new Chinese voices generally, not just Lilian. Offline system voices and prerecorded audio are useful outdoors without mobile data.

Spoken neighbor names, floors and destinations may be personal data. Prerecording fictional demo lines avoids sending real residents' details for that workflow. Real-time cloud speech sends content to providers and needs an accurate consent/retention explanation. Vendor no-logging statements are not a complete privacy policy. Current Doubao routing and test-conversation logging must be described using current implementation evidence.

Downloading enhanced voices requires system Settings; the App cannot download them for the user. A short illustrated guide and assistance from family/community staff were proposed. Playback mode ignores the hardware silent switch; test this on devices and make the App speech toggle clear. The note proposed a main-screen mute control but did not establish approval or implementation.

Every spoken line needs natural Cantonese, Mandarin and English wording; reading Cantonese phrases with a Mandarin voice is not localization.

### Reported Mandarin/Cantonese system issue

Developer reports described Mandarin output becoming Cantonese when Siri or spoken-content Chinese preferences were Cantonese on iOS 18–26, including a March 2026 report on 26.2.1. Upgraded/restored devices appeared affected; identifier-based selection was not proven to fix it. These were reports, not a universal reproduced result. Prerecorded audio avoids this particular system-synthesizer issue. References: [772348](https://developer.apple.com/forums/thread/772348), [788218](https://developer.apple.com/forums/thread/788218), [792744](https://developer.apple.com/forums/thread/792744), [801554](https://developer.apple.com/forums/thread/801554).

## 4. Original implementation tiers and effort estimates

### Tier 1: local controls, estimated 1–2 days plus device testing

Add speech enable/disable with immediate stop, three languages, installed-voice list with quality/preview, and three speeds. Respect saved compatible choices, otherwise prefer premium, enhanced, then basic. Recognize both `yue-HK` and `zh-HK`. Recheck downloads on foreground return.

Guide users to Settings → Accessibility → Read & Speak → Voices on iOS 26, or Spoken Content → Voices on iOS 18, then the relevant Chinese locale. References: [iOS 26 Hong Kong guide](https://support.apple.com/zh-hk/guide/iphone/iph96b214f0/26.0/ios/26.0), [iOS 18 guide](https://support.apple.com/zh-hk/guide/iphone/iph96b214f0/18.0/ios/18.0).

The public [voice API](https://developer.apple.com/documentation/avfaudio/avspeechsynthesisvoice) did not expose download initiation or an available-but-uninstalled catalog. The [accessibility Settings API](https://developer.apple.com/documentation/accessibility/accessibilitysettings/feature) did not provide a Voices deep link; [DTS warned about private links](https://developer.apple.com/forums/thread/691712).

The dated catalog showed about 47 MB and under 80 MB peak memory for premium Cantonese versus roughly 280 MB for Ava. Package size alone does not establish quality. Tier 1 solved controls and offline availability, not proven naturalness.

### Tier 2A: prerecorded demo, estimated 2–3 days

Prepare all demo lines in three languages. Blind-test three Chirp candidates (Kore/Aoede/Leda), two MiniMax candidates (KindWoman/GentleLady), and premium Sinji as baseline, optionally ElevenLabs. Ask 3–5 older/native listeners to rate clarity, pace and warmth from 1–5. Package the selected recordings, estimated within tens of MB, with system fallback.

The original budget example was 300 lines x 30 characters x 3 languages = 27,000 characters, below the recorded Google free quota. MiniMax was a comparison candidate, not a proven winner. Verify preview-service guarantees, Hong Kong access, same-name cross-language timbre and commercial redistribution terms. The small [cantonese-dubbing-desk project](https://raw.githubusercontent.com/wongsir1011/cantonese-dubbing-desk/main/README.md) was weak availability evidence and used Azure by default, not Chirp.

A human community-worker/resident recording was another untested proposal; variable names/times complicate it. Label prerecorded AI demo speech honestly.

### Tier 2B: real-time cloud, originally deferred

Use a relay to protect credentials, disclose uploaded text and cache completed speech. The original note considered Google/Azure based on then-recorded quotas/privacy, while acknowledging Azure's 20 requests/minute free-tier limit. It floated manually entered keys for internal testing only; this was not a public-release recommendation. Current code has since implemented server-mediated real-time speech.

### Tier 3: local open models, originally deferred

The 114 MB sherpa Cantonese model lacked located licensing/evaluation. canto-tts-nano was roughly 764 MB and Python-only, making iOS porting unattractive for the deadline. Kokoro's cited iPhone 12 Pro result generated three seconds of audio in about 1.4 seconds excluding preprocessing; iPhone 11 remained untested. Short utterances below 10–20 tokens were a documented weakness, and Mandarin self-ratings were poor. Larger models were proposed only for server/computer batch generation. Model capability and hardware feasibility require fresh measurement rather than an absolute claim that every phone can or cannot run them.

## 5. Corrections retained from the original review

1. iOS 26's English menu is Read & Speak; the initial Chinese translation was wrong. See the [simplified-Chinese guide](https://support.apple.com/zh-cn/guide/iphone/iph96b214f0/26.0/ios/26.0).
2. Roughly 46 MB applied to newer premium Cantonese entries; older premium Sinji was 25 MB. Wing/Fung appeared only in newer entries.
3. Omitting an explicit voice uses device defaults, not always Mandarin Tingting; English devices could use Samantha.
4. The reported language-selection regression FB20271264 was a developer report Apple could not reproduce: [804648](https://developer.apple.com/forums/thread/804648).
5. WWDC established Siri API unavailability, not necessarily absence from every enumerated list; no evidence established community consensus on Siri Cantonese superiority.
6. The quiet-volume report concerned new Chinese voices broadly. Lilian's trailing-word omission report was from 2022; current status was unknown.
7. Azure HD covered many languages; only HD Flash had the narrower language scope cited. The dated Cantonese HD absence was a separate claim.
8. The paper tested Edge-TTS; treating it as Azure and calling it mechanical were inferences. It did not directly measure naturalness against Apple, used 10 raters/50 samples with overlapping intervals, and was not the only native-Cantonese study: [another paper](https://arxiv.org/pdf/2206.04922).
9. Chirp Cantonese did not support explicit pause tags or custom pronunciation in the reviewed interface; punctuation was the documented alternative.
10. cantonese-dubbing-desk defaulted to Azure, with Chirp optional, and had negligible community adoption in that observation.
11. PCM discussed mixed-language/tone issues, not specifically polyphonic characters. `language_boost="Chinese,Yue"` came from official MiniMax documentation. Best-in-Hong-Kong and absence of any zero-retention option were not established.
12. ElevenLabs scores were Turbo 1329 and v4 1326, statistically tied. First-ever Cantonese support was inferred. Slow tags or playback-rate changes were possible even without a speed slider.
13. sherpa Swift Package Manager support began at v1.13.5 on 2026-08-11 in the cited record, not v1.13.8. Sentence-ending fixes were PRs 2558/2559, not issue 589.
14. Kokoro and Chirp scores overlapped; superiority was not established.
15. Polly's low score was relative to newer products and English-only, not an all-language judgment.
16. Excluding Personal Voice on iPhone 11 relied on Apple's device list, not simulator behavior.

Unresolved then: premium Cantonese listening quality; Wing/Fung availability on iOS 18; the Mandarin bug after 26.3 and identifier workaround; simultaneous premium-voice installation; independent Cantonese comparisons; commercial recording redistribution; actual iPhone 11 latency; Hong Kong Google Cloud access.

## 6. Proposed next steps at the research date

1. Spend half a day listening on iPhone 11, ideally comparing iOS 18/26, with available Sinji/Wing/Fung/Aasing voices and actual Cantonese outing/invitation/mixed-number phrases.
2. Test Mandarin while Siri is set to Cantonese.
3. Implement Tier 1 and prepare natural text in all three languages with B.
4. Compare cloud candidates, including the [MiniMax Cantonese demo](https://www.minimax.io/audio/text-to-speech/cantonese), with 3–5 blind listeners; Google signup was expected.
5. Choose prerecordings only from those results and retain system fallback.
6. Describe prerecorded versus live speech honestly in the pitch. Current implementation and actual validation now take precedence over this old plan.
