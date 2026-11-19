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

## Update feed and signing key

Installed copies update themselves from the Sparkle feed at `https://orlandofua.github.io/StockMonitor/appcast.xml`, which GitHub Pages serves from `appcast.xml` on the `gh-pages` branch. Every update is signed with one EdDSA key (ADR [0015](docs/adr/0015-in-app-updates-with-sparkle.md)). The release workflow adds a feed entry for each release; the README describes [the setup](README.md#update-feed). The procedures below are done by hand by the repository owner.

The commands use the Sparkle tools that SwiftPM downloads on the first `./build.sh`, in `.build/artifacts/sparkle/Sparkle/bin`, and are run from the repository root.

### Pull a bad release

There is no automatic rollback. Sparkle never installs an older version, so copies that already have the bad release keep it until a fixed release reaches them. Removing the entry from the feed only stops copies that do not have it yet from being offered it.

1. Make sure no release run is in progress, so its feed push does not race with yours: `gh run list --workflow release.yml --limit 3`.
2. Check out the feed in a separate folder, so your working tree is not touched:

   ```sh
   git fetch origin gh-pages
   git worktree add --detach "$TMPDIR/gh-pages" origin/gh-pages
   ```

3. Open `$TMPDIR/gh-pages/appcast.xml` and delete the whole `<item>` ... `</item>` block whose `<sparkle:shortVersionString>` is the bad version. Leave the other items as they are. Commenting the block out with `<!--` and `-->` also works; `scripts/add-appcast-item.sh` skips commented-out items.
4. Check that the feed is still well-formed and no longer offers the version. The first command prints nothing when the XML is fine, and the second prints `0`:

   ```sh
   xmllint --noout "$TMPDIR/gh-pages/appcast.xml"
   xmllint --xpath "count(/rss/channel/item[*[local-name()='shortVersionString']='X.Y.Z'])" "$TMPDIR/gh-pages/appcast.xml"
   ```

5. Commit and push without force. If the push is rejected because a release run pushed in the meantime, run `git -C "$TMPDIR/gh-pages" pull --rebase origin gh-pages` and push again.

   ```sh
   git -C "$TMPDIR/gh-pages" commit -am "chore(appcast): pull vX.Y.Z"
   git -C "$TMPDIR/gh-pages" push origin HEAD:refs/heads/gh-pages
   git worktree remove "$TMPDIR/gh-pages"
   ```

6. Mark the GitHub release as a pre-release, so the README's "latest release" link no longer points at it: `gh release edit vX.Y.Z --prerelease`. Keep its zip; deleting it only breaks downloads of that version.
7. After about 10 minutes, when the GitHub Pages cache has expired, check that the live feed no longer lists the version: `curl -fsS https://orlandofua.github.io/StockMonitor/appcast.xml | grep shortVersionString`.
8. Ship the fix through the normal pull request flow with a `release:patch` label (or a larger bump if needed). Its version and build number are higher than the bad release's, so copies that already installed the bad release update to it.
9. If the bad release broke the updater itself, for example so that **Check for Updates…** fails or the update never installs, those copies cannot reach the fix on their own. Say so at the top of the fixed release's notes and point users to [Update by hand](README.md#update-by-hand).

To undo a pull, revert the feed commit on `gh-pages` with `git revert` in the same kind of worktree, and push it the same way.

### Back up the signing key

The `SPARKLE_ED_PRIVATE_KEY` secret cannot be read back from GitHub. If the key is lost, installed copies can never be updated through the feed again, and every user has to install a new build by hand. Keep one offline backup in the owner's password manager, and check it.

1. Export the key from the login keychain, where `generate_keys` stored it when it was created:

   ```sh
   .build/artifacts/sparkle/Sparkle/bin/generate_keys -x private-key.txt
   ```

2. In your password manager, create a secure note named "StockMonitor Sparkle EdDSA private key". Paste the contents of `private-key.txt` (one line of base64), the public key (`gh variable get SPARKLE_PUBLIC_ED_KEY`), and today's date.
3. Check the backup, not the exported file. Copy the key from the password manager into a new file, `backup-key.txt`, then sign a test file with it and verify the signature against the public key that the app trusts. The last command prints that the signature is valid; anything else means the backup does not match.

   ```sh
   echo "backup check" > backup-check.txt
   sig="$(.build/artifacts/sparkle/Sparkle/bin/sign_update --ed-key-file backup-key.txt -p backup-check.txt)"
   swift scripts/verify-ed-signature.swift "$(gh variable get SPARKLE_PUBLIC_ED_KEY)" "$sig" backup-check.txt
   ```

4. Delete the files: `rm private-key.txt backup-key.txt backup-check.txt`. Never commit them.
5. Optional, once the backup is checked: delete the copy in the login keychain. In Keychain Access, delete the password item named `https://sparkle-project.org` with the account `ed25519`. Afterwards `generate_keys -p` no longer finds a key.

To restore the secret from the backup, for example after it was deleted by mistake, save the key from the password manager to `private-key.txt`, run `gh secret set SPARKLE_ED_PRIVATE_KEY < private-key.txt`, and delete the file. To sign by hand on a Mac, import it into the login keychain with `generate_keys -f private-key.txt`.

### Replace a lost or leaked key

Installed copies trust only the public key they were built with. Sparkle accepts a new key through an update only when the update is code-signed with the same Apple identity as the installed app, and ad-hoc signatures differ for every build. Until Developer ID signing ([#12](https://github.com/orlandofua/StockMonitor/issues/12)) lands, a new key therefore cannot reach installed copies through an update: every user has to install the first release signed with the new key by hand. Only replace the key when it is lost (no keychain copy and no backup) or may have leaked.

1. If the key may have leaked, delete the secret at once, so no further release is signed with it: `gh secret delete SPARKLE_ED_PRIVATE_KEY`. Release runs fail in their first step until step 4 is done, so hold merges or label them `skip-release`.
2. Create the new key pair under a new keychain account, so `generate_keys` does not return the old key, and print its public key:

   ```sh
   .build/artifacts/sparkle/Sparkle/bin/generate_keys --account stockmonitor-YYYY-MM-DD
   .build/artifacts/sparkle/Sparkle/bin/generate_keys --account stockmonitor-YYYY-MM-DD -p
   ```

3. Export it with `generate_keys --account stockmonitor-YYYY-MM-DD -x private-key.txt`, and replace the old backup in the password manager with it, as in [Back up the signing key](#back-up-the-signing-key). Keep the old entry, marked as retired, if the key was lost rather than leaked.
4. Store the new pair. The secret and the variable must change together; the release workflow checks the zip's signature against the public key in the built app and fails if they do not match.

   ```sh
   gh secret set SPARKLE_ED_PRIVATE_KEY < private-key.txt
   gh variable set SPARKLE_PUBLIC_ED_KEY --body '<new public key>'
   rm private-key.txt
   ```

5. Check the backup of the new key as in step 3 of [Back up the signing key](#back-up-the-signing-key).
6. Ship a release through the normal pull request flow. It embeds the new public key in `SUPublicEDKey`. At the top of its release notes, tell users to install it by hand ([Update by hand](README.md#update-by-hand)). Copies with the old key are offered this release and refuse it with "The update is improperly signed and could not be validated"; after a manual install, they update normally again.
