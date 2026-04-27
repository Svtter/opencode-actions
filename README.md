# opencode-actions

Reusable GitHub Actions for installing and running OpenCode in other repositories.

This repository is licensed under Apache 2.0.

## TLDR

Write this in your CI.yaml

```yaml
- name: Run OpenCode review
  uses: Svtter/opencode-actions/review@v1
  with:
    github-token: ${{ secrets.GITHUB_TOKEN }}

    # only one is enough.
    zhipu-api-key: ${{ secrets.ZHIPU_API_KEY }}
    opencode-go-api-key: ${{ secrets.OPENCODE_GO_API_KEY }}
```

You'll get a automatic reviewer in Chinese.

## What it includes

- `review`: opinionated PR review wrapper with built-in prompt and model defaults
- `feature-missing`: audits PR implementation against linked issue spec to find missing features
- `github-run-opencode`: one-step wrapper for the common `opencode github run` workflow
- `setup-opencode`: installs OpenCode, restores a dedicated cache, and exports the binary path
- `run-opencode`: runs `opencode` with optional retry logic for flaky GitHub network failures

## Current scope

- Linux only
- installer-based bootstrap via `https://opencode.ai/install`
- cache is best-effort and does not pin an exact OpenCode version
- by default `setup-opencode` ignores unrelated `opencode` binaries already present on `PATH`; set `allow-preinstalled: true` only if you explicitly trust the runner image

## github-run-opencode

Use this when you want the shortest consumer workflow for `opencode github run`.

### Common inputs

| Input | Default | Description |
| --- | --- | --- |
| `model` | `MODEL_NAME`, else `zhipuai-coding-plan/glm-5.1` | Exported as `MODEL` before `opencode github run`; explicit input still overrides |
| `fallback-models` | empty | Optional ordered fallback models, filtered by available provider API keys |
| `model-timeout-seconds` | `300` | Per-model timeout before rotating to the next fallback candidate when fallbacks are configured; `0` disables it |
| `fallback-on-regex` | timeout regex | Rotate to the next fallback candidate when output matches this regex |
| `prompt` | built-in PR review template | Exported as `PROMPT` before `opencode github run` |
| `github-token` | empty | Exported as `GITHUB_TOKEN` before `opencode github run` |
| `zhipu-api-key` | empty | Exported as `ZHIPU_API_KEY` before `opencode github run` |
| `opencode-go-api-key` | empty | Exported as `OPENCODE_GO_API_KEY` before `opencode github run` |
| `use-github-token` | `true` | Exported as `USE_GITHUB_TOKEN` before `opencode github run` |
| `attempts` | `3` | Total attempts before failing |
| `retry-profile` | `github-network` | Built-in retry preset for common GitHub failures |
| `timeout-seconds` | `600` | Maximum execution time for `opencode github run`; `0` disables it |
| `working-directory` | empty | Optional working directory before running OpenCode |

`github-run-opencode` also accepts the setup-related inputs from `setup-opencode`, such as `cache`, `cache-key`, `install-attempts`, `install-url`, and `allow-preinstalled`.

## review

Use this when you want the simplest PR review setup.

- built-in `prompt` review template (same as `github-run-opencode`)
- built-in `MODEL` resolution: explicit `model` input, else `MODEL_NAME`, else `zhipuai-coding-plan/glm-5.1`
- built-in `timeout-seconds` default: `600` (10 minutes)
- optional ordered `fallback-models` for timeout-driven model rotation
- still allows overriding any input when needed

When `fallback-models` is set, the wrapper keeps `model` as the first choice and only rotates to the next candidate when the current model times out or emits a timeout-like error. Candidates whose provider key is unavailable are skipped automatically.

## feature-missing

Use this alongside `review` to audit whether a PR's implementation covers all requirements from the linked issue spec.

- automatically reads the linked issue body as the feature spec via `gh pr view`
- if no linked issue, extracts requirements from the PR title and body
- classifies gaps by severity: CRITICAL, MEDIUM, LOW
- shares the same inputs and cache as `review`/`github-run-opencode`

```yaml
- name: Run feature missing audit
  uses: Svtter/opencode-actions/feature-missing@v1
  with:
    github-token: ${{ secrets.GITHUB_TOKEN }}
    zhipu-api-key: ${{ secrets.ZHIPU_API_KEY }}
    opencode-go-api-key: ${{ secrets.OPENCODE_GO_API_KEY }}
```

## setup-opencode

### Inputs

| Input | Default | Description |
| --- | --- | --- |
| `install-url` | `https://opencode.ai/install` | Installer URL used to bootstrap OpenCode |
| `install-dir` | computed | Directory where `opencode` will be installed |
| `xdg-cache-home` | computed | Dedicated XDG cache directory |
| `cache` | `true` | Enable `actions/cache` for install and cache directories |
| `cache-key` | `v1` | Cache key suffix used to invalidate installer caches |
| `install-attempts` | `3` | Total installer attempts |
| `allow-preinstalled` | `false` | Reuse an existing trusted `opencode` already present on `PATH` |

The internal cache key also includes a hash of `install-url`, so changing installer sources does not silently reuse an older cache entry.

### Outputs

| Output | Description |
| --- | --- |
| `opencode-path` | Resolved absolute path to `opencode` |
| `install-dir` | Resolved install directory |
| `xdg-cache-home` | Resolved XDG cache directory |
| `cache-hit` | Whether `actions/cache` restored a hit |
| `version` | `opencode --version` output |

## run-opencode

### Inputs

| Input | Default | Description |
| --- | --- | --- |
| `args` | empty | Space-delimited arguments passed to `opencode` |
| `working-directory` | empty | Working directory used before invoking OpenCode |
| `attempts` | `1` | Total attempts before failing |
| `retry-on-regex` | empty | Retry only when command output matches this regex |
| `retry-profile` | empty | Built-in retry preset such as `github-network` |
| `retry-delay-seconds` | `15` | Base delay used between retries |
| `opencode-path` | `opencode` | Explicit binary path from `setup-opencode` |

`run-opencode` intentionally keeps provider secrets and model selection in workflow `env:` so the action stays generic.
In the common same-job case, `setup-opencode` already exports `opencode` to `PATH`, so you do not need to pass `opencode-path` into `run-opencode`.

## Usage

Public consumers should reference the subdirectory action path:

```yaml
uses: Svtter/opencode-actions/review@v1
uses: Svtter/opencode-actions/feature-missing@v1
uses: Svtter/opencode-actions/github-run-opencode@v1
uses: Svtter/opencode-actions/setup-opencode@v1
uses: Svtter/opencode-actions/run-opencode@v1
```

```yaml
- name: Run OpenCode review
  uses: Svtter/opencode-actions/review@v1
  with:
    github-token: ${{ secrets.GITHUB_TOKEN }}
    zhipu-api-key: ${{ secrets.ZHIPU_API_KEY }}
    opencode-go-api-key: ${{ secrets.OPENCODE_GO_API_KEY }}
```

More examples live in `examples/`.

If you need more control, you can still use `setup-opencode` and `run-opencode` directly. For example, pass `opencode-path` explicitly when reusing a binary from another job or a custom location.

The PR review example intentionally skips forked pull requests because repository secrets are not exposed there by default.
The comment-command example also skips forked pull requests for the same reason.
The comment-command example only allows `OWNER`, `MEMBER`, and `COLLABORATOR` comments to trigger the workflow.

## Local verification

```bash
bash tests/test.sh
```

## CI

This repository includes a CI workflow that:

- runs `shellcheck` on every bundled shell script
- runs the local shell-based regression suite
- smoke-tests all four actions through `uses: ./setup-opencode`, `uses: ./run-opencode`, `uses: ./github-run-opencode`, `uses: ./review`, and `uses: ./feature-missing`

## Release Policy

- publish immutable releases as `v1.0.0`, `v1.1.0`, `v1.1.1`, and so on
- consumers can pin to `@v1` for compatible updates
- security-sensitive consumers should pin to a full commit SHA instead of a moving major tag
- this repository updates the repo-wide major tag like `v1` when a semver GitHub release is published

## Publishing Checklist

1. Push the repository publicly.
2. Verify `CI` passes on `main`.
3. Create a GitHub release with a semver tag such as `v1.0.0`.
4. Confirm the `Update Major Tag` workflow moved `v1` to that release.
5. Use `owner/repo/review@v1` for the simplest review setup, `owner/repo/feature-missing@v1` for spec coverage audit, `owner/repo/github-run-opencode@v1` for generic `github run`, or `owner/repo/setup-opencode@v1` plus `owner/repo/run-opencode@v1` for more control.

The initial release-notes template lives at `docs/releases/v1.0.0.md`.

## Limitations

- `args` is parsed as a space-delimited string, so keep complex text in environment variables like `PROMPT`
- the installer is external, so cache invalidation uses `cache-key` instead of a guaranteed version pin
- first version is optimized for GitHub-hosted or Linux self-hosted runners
