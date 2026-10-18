# Contributing

## Check your commit identity

Before committing, configure your own name and a verified email associated with your GitHub account, or your GitHub-provided private `noreply` address. Use repository-local settings:

```sh
git config --local user.name "YOUR_NAME"
git config --local user.email "YOUR_GITHUB_COMMIT_EMAIL"
git var GIT_AUTHOR_IDENT
git var GIT_COMMITTER_IDENT
```

Replace the placeholders with your own identity. Never copy another contributor's identity or use a shared tool identity such as `Codex <codex@openai.com>`. For work performed with an agent, confirm the requesting contributor's identity before committing. Preserve other contributors' authorship.

See GitHub's [commit email guide](https://docs.github.com/en/account-and-profile/how-tos/email-preferences/setting-your-commit-email-address).

## Earlier documentation attribution

The October 2026 English documentation, language checks, and beginner installation instructions were AI-assisted work requested and directed by `patrick3432348016` (Patr1ckGod). Eight commits mistakenly used the generic Codex identity: `af94d09`, `b2f3017`, `717b981`, and `b3d803d` on main; `b55ff87`, `016c07e`, `29a3d57`, and `e520a3f` on the historical default branch.

The repository's [.mailmap](.mailmap) maps that exact name/email pair to Patrick's confirmed account identity for tools that honor mailmap. It preserves the original commit objects and hashes. This mapping does not authorize attributing future contributors' work to Patrick; each contributor must use their own identity. GitHub's web statistics must be checked separately from local Git output.

Inspect the mapped history with `git log --format='%h %aN <%aE> %s'` or `git shortlog -sne HEAD`. See the [Git mailmap reference](https://git-scm.com/docs/gitmailmap) for mapping behavior.
