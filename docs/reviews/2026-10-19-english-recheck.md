# English-only material recheck — 19 October 2026

## Scope and findings

This follow-up checked both the integrated `main` branch (starting at `b2f3017`) and the repository's default `prototype/ios-3d-diorama` branch (starting at `b42f6e5`). The default branch's newly added beginner deployment notice was preserved.

The earlier translation was incomplete: the historical default branch still contained Chinese source comments, and maintainer-facing terminal messages, test labels, property-list comments, developer-client text, and the historical video review page had not all been translated. This pass translates those omissions, including 2,969 comment segments across 163 default-branch source files. It also replaces Chinese punctuation in otherwise English comments.

The integrated app still supports Cantonese, Mandarin, and English. The older prototype retains its existing language capabilities; translating its material does not upgrade it to main. No default-branch setting or production service was changed.

## Necessary Chinese retained

The checked-in `tools/language-exceptions.json` identifies each remaining text file, its reason, and a fingerprint of its reviewed CJK content. The permitted categories are:

- Cantonese/Mandarin app labels, speech, permission descriptions, localized errors, language-recognition vocabulary, and proper names.
- Original multilingual test inputs and expected localized output. Human-readable test descriptions and diagnostic labels are now English.
- Original voice examples shown with English explanations, including the developer client's Cantonese examples and fixed-rule test inputs.
- Original map and building names, provider/source fields, and full-width punctuation recognized by text parsers.
- Historical video captions, on-screen app quotations, proper names, and recording alignment metadata.
- Two legacy Chinese documentation filenames retained for link compatibility; their contents redirect to English guides.

Original screenshots, recordings, binary media, raw audit data, and archived patches are preserved as evidence. They are explicitly outside prose translation. Private configuration, credential-related files, and recording logs are excluded before reading; no claim is made about their language. Browser-owned controls, such as the native file chooser, follow the browser/OS language.

## Repeatable check

From the repository root:

```sh
python -m pip install -r tools/requirements-language.txt
python tools/check_repository_language.py
python tools/test_repository_language.py
```

The checker inspects tracked UTF-8 text, rejects unreviewed CJK text and filenames, and independently rejects CJK in code comments/docstrings even in localized source files. Missing tracked text fails the check rather than silently passing a sparse checkout. Original media/evidence and private files are excluded before opening them. The dependency is development-only and does not change server runtime dependencies.

**Do not regenerate exception fingerprints merely to make the check pass.** Inspect the actual change and confirm why Chinese is necessary. Changed Chinese text requires review; a fingerprint match is a regression check, not proof of translation quality. The checker is available for manual use; this change does not add a CI workflow.

## Verification

- Both branch scans: zero unreviewed CJK findings and zero CJK comments/docstrings after correction.
- Five negative-control tests passed: unexpected Chinese prose, Chinese comments despite a refreshed exception, changed localized text, private-file exclusion, and missing tracked text.
- Existing-source comparisons found no changes to non-text Swift/JavaScript/SQL tokens or Python structure after normalizing string constants. iOS property-list values are unchanged. A pre-existing invalid double-hyphen inside an XML comment was removed while translating the comment.
- Shell syntax checks passed for six changed scripts on main and eleven on the historical branch.
- The existing browser state suite passed against each branch's integrated client using an ephemeral path adapter for the archived B-package test. It covers warning scope, credential-import behavior with synthetic data, interruption, late audio, microphone-stop races, and local microphone isolation. No live microphone or provider connection was used.
- The English voice-client and historical review pages were rendered at 1440 and 390 px widths with mocked/blocked network access: no page overflow or JavaScript errors. No credentials were loaded and no feedback was submitted.
- Color-contrast diagnostics ran successfully; only report labels changed.
- Main's offline Windows server suite remains **114 tests: 110 passing, 3 failures, 1 error**, matching the known `%-d` leave-date formatting problem. No new failure was introduced by the translated developer page.
- iOS/Xcode and real-device validation were not run on Windows. Live Supabase and provider tests were not run. The original dirty local checkout remains untouched.

## Acceptance

**P1 / SHOULD HAVE / MODIFY:** This closes an English-material consistency gap in Prototype/demo and Appropriate technical component (20% each). Acceptance is zero unexplained Chinese in the audited material, readable English operator text, preserved application language behavior, and recorded verification limits. It does not establish product reliability, social impact, or a numerical judging-score improvement.
