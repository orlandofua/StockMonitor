# Contributing

## Workflow

1. Branch off an up-to-date `main`. Name the branch after the change type and issue, for example `fix/6-validate-symbol`, `feature/9-alerts`, `chore/8-parse-chart-response`, or `docs/11-install-and-release-docs`.
2. Run `./test.sh` and `./build.sh` locally. CI runs the same two scripts on every pull request (ADR [0008](docs/adr/0008-continuous-integration-on-github-actions.md)).
3. Write commit messages and the pull request title in the [Conventional Commits](#commit-messages) format. CI checks both.
4. Open a pull request into `main` that links its issue (`Closes #N`), and give it exactly one release label (see below).
5. Record significant architecture decisions as a new ADR in [`docs/adr`](docs/adr/README.md).

## Commit messages

New commits and pull request titles follow [Conventional Commits 1.0.0](https://www.conventionalcommits.org/en/v1.0.0/) (ADR [0013](docs/adr/0013-use-conventional-commits.md)). The pull request title counts because a squash merge uses it as the commit message on `main`.

```
<type>(<optional scope>)!: <subject>

<optional body>

<optional footers>
```

| Type | Use it for |
| --- | --- |
| `feat` | A new feature or user-visible capability |
| `fix` | A bug fix |
| `docs` | Documentation only, including ADRs |
| `test` | Adding or fixing tests |
| `refactor` | A code change that neither fixes a bug nor adds a feature |
| `perf` | A performance improvement |
| `build` | `build.sh`, `Package.swift`, or other build changes |
| `ci` | GitHub Actions workflows and CI scripts |
| `chore` | Other maintenance that does not touch the app |
| `style` | Formatting only, no behavior change |
| `revert` | Reverting an earlier commit |

Rules:

- Types are lower case. The scope is optional and is a single word in parentheses, such as `(stream)` or `(menu)`.
- Put exactly one space after the colon. The subject is required, uses the imperative ("add", not "added"), and does not end with a period.
- The first line is at most 72 characters.
- Mark a breaking change with `!` before the colon, or with a `BREAKING CHANGE: <description>` footer. Breaking changes usually also need the `release:major` label.
- Messages that git or GitHub write for you are allowed as they are: `Merge ...`, `Revert "..."`, `fixup! ...`, `squash! ...`, and `amend! ...`.

Examples:

```
feat: add launch at login
fix(stream): reconnect after wake
ci: publish a release when a PR merges to main
feat!: drop macOS 13
docs(adr): record the Conventional Commits decision
```

### Local hook

Enable the versioned `commit-msg` hook once per clone, so a bad message is refused before it is committed:

```sh
scripts/install-hooks.sh   # runs: git config core.hooksPath .githooks
```

After that, `git commit -m "bad message"` is refused with the expected format, and `git commit -m "chore: test hook"` works. This setting makes git use `.githooks` instead of `.git/hooks`, so move any personal hooks there. Use `git commit --no-verify` to skip the hook in an emergency; CI still checks the commit. To check a message by hand, run `echo "fix: x" | scripts/check-commit-msg.sh`.

### Fixing a failing check

The **Commit messages** workflow fails when the pull request title or any commit in the pull request does not follow the format. Its log names each offending commit's SHA and message.

- **Title:** edit the pull request title on GitHub. The check re-runs on its own; no push is needed.
- **Last commit:** `git commit --amend`, fix the message, then `git push --force-with-lease`.
- **Older commits:** `git rebase -i origin/main`, change `pick` to `reword` for each bad commit, fix the messages, then `git push --force-with-lease`.

Commits that were already on `main` before this rule are never checked.

## Release labels

Merging a pull request into `main` publishes a GitHub Release automatically (ADR [0009](docs/adr/0009-release-on-merge-with-label-driven-semver.md)). The pull request's label decides the version bump, so set it before you merge. Labels added after the merge have no effect.

| Label | Use it for | Example |
| --- | --- | --- |
| `release:patch` | Bug fixes and internal changes that users may notice but that add nothing new | `v1.2.3` to `v1.2.4` |
| `release:minor` | A new user-facing feature or setting that keeps existing behavior working | `v1.2.3` to `v1.3.0` |
| `release:major` | A change that breaks existing behavior, such as dropping a supported macOS version or resetting saved settings | `v1.2.3` to `v2.0.0` |
| `skip-release` | Changes that do not alter the app: docs, CI, ADRs, or scripts that do not affect the build | no release |

Rules:

- A pull request with no release label gets a patch release. Pick a label on purpose instead of relying on that.
- If several labels are present, `skip-release` wins, then the largest bump. Use one label to keep this obvious.
- A `skip-release` change is still included in the next release built from a later pull request, but it is left out of the release notes (`.github/release.yml` excludes the label).
- Release notes are generated from pull request titles and grouped by the `enhancement`, `bug`, `tech-debt`, `ci`, and `documentation` labels, so write a title that makes sense to users.
- Do not create or move `vMAJOR.MINOR.PATCH` tags by hand. The workflow bumps the highest such tag and fails if the next tag already exists. Other tags, such as `v1.1.0-beta`, are ignored.
