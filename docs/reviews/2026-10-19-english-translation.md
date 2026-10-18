# English documentation and comment review — 19 October 2026

## Scope

The repository documentation, setup instructions, historical design notes, review prose, and source comments have been translated into English. The integrated application is on `main`; the implementation baseline for this translation was `f8d63c9749ff5fc12b1d887afc3510ca2cc36dfd`, followed by the English overview and installation-guide commit `af94d09`.

The app retains Cantonese, Mandarin, and English. Runtime strings, multilingual test inputs, map names, recordings, screenshots, archived patch files, and the original machine-readable audit record are preserved. Chinese voice examples remain alongside English explanations where translating the input would change the example. Legacy Chinese documentation filenames redirect readers to the English canonical guides so existing links continue to work.

Historical documents retain their dates and distinguish original findings from current implementation. They do not establish new resident research, deployment, privacy guarantees, or independent device validation. No credentials, private provider configuration, account databases, or conversation logs were read for this work.

## Verification

- Translated 3,595 extracted comment/docstring segments across 179 source files. Comparing the original and translated token streams found no changes outside comments/docstrings. Python syntax trees, with documentation strings removed, also matched.
- Translated the remaining comments in `.gitignore` and `server/requirements.txt`; ignore patterns and dependency pins are unchanged.
- SQL statements in the historical backend design document match the originals after removing SQL comments. Migration changes are comments only; no database migration was executed.
- Repository Markdown links resolve to tracked files or directories, including media intentionally absent from the sparse working copy.
- No Chinese source comments remain in the checked Swift, Python, shell, JavaScript, SQL, HTML, CSS, or project configuration files. Remaining Chinese documentation text consists of original voice-input examples.
- The historical HTML layout sketch was rendered at 1200, 920, and 375 px viewport widths. English labels have sufficient space, with no detected card overflow or JavaScript errors. This is a documentation preview, not iOS validation.
- `git diff --check` passed.

## Offline server tests

Run from `server/` on Windows with Python 3.12:

```sh
python -m unittest discover -s tests -p 'test_*.py'
```

Result: **114 tests run; 110 passed, 3 failures, 1 error.** This matches the previously recorded Windows baseline. The affected cases exercise leave-date formatting with the existing unsupported Windows format `%-d` in `assistant/service.py`:

- `test_rename_and_leave_require_confirmation`
- `test_app_command_goes_through_b_confirmation`
- `test_leave_and_rename_need_confirmation_then_write`
- `test_text_demo_still_available`

This documentation change does not fix or hide those failures. iOS/Xcode checks and real-device flows were not run on Windows. No live provider or production Supabase tests were run.

## Acceptance and judging relevance

**P1 / SHOULD HAVE / MODIFY:** English project material improves reviewability and evidence consistency in the official Prototype/demo and Appropriate technical component categories (20% each). Acceptance is readable English documentation with preserved behavior and explicit limitations; it does not establish a numerical score increase. GenAI baseline comparisons, target-resident validation, deployed privacy controls, and the known Windows test failures remain separate unresolved work.
