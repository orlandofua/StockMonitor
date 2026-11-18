# Contributing

## Workflow

1. Branch off an up-to-date `main`. Name the branch after the change type and issue, for example `fix/6-validate-symbol`, `feature/9-alerts`, `chore/8-parse-chart-response`, or `docs/11-install-and-release-docs`.
2. Run `./test.sh` and `./build.sh` locally. CI runs the same two scripts on every pull request (ADR [0008](docs/adr/0008-continuous-integration-on-github-actions.md)).
3. Open a pull request into `main` that links its issue (`Closes #N`), and give it exactly one release label (see below).
4. Record significant architecture decisions as a new ADR in [`docs/adr`](docs/adr/README.md).

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
