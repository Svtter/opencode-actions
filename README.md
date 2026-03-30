# opencode-actions

Reusable GitHub Actions for installing and running OpenCode in other repositories.

This repository is licensed under Apache 2.0.

## What it includes

- `setup-opencode`: installs OpenCode, restores a dedicated cache, and exports the binary path
- `run-opencode`: runs `opencode` with optional retry logic for flaky GitHub network failures

## Current scope

- Linux only
- installer-based bootstrap via `https://opencode.ai/install`
- cache is best-effort and does not pin an exact OpenCode version
- by default `setup-opencode` ignores unrelated `opencode` binaries already present on `PATH`; set `allow-preinstalled: true` only if you explicitly trust the runner image

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
| `retry-delay-seconds` | `15` | Base delay used between retries |
| `opencode-path` | `opencode` | Explicit binary path from `setup-opencode` |

`run-opencode` intentionally keeps provider secrets and model selection in workflow `env:` so the action stays generic.

## Usage

Public consumers should reference the subdirectory action path:

```yaml
uses: your-org/opencode-actions/setup-opencode@v1
uses: your-org/opencode-actions/run-opencode@v1
```

```yaml
- name: Setup OpenCode
  id: setup
  uses: your-org/opencode-actions/setup-opencode@v1
  with:
    cache: true
    cache-key: review-v1
    install-attempts: 3

- name: Run OpenCode review
  uses: your-org/opencode-actions/run-opencode@v1
  with:
    args: github run
    attempts: 3
    retry-on-regex: unable to access 'https://github.com/|Failed to connect to github\.com port 443|Couldn't connect to server|Connection timed out|Operation timed out
    opencode-path: ${{ steps.setup.outputs.opencode-path }}
  env:
    MODEL: zhipuai-coding-plan/glm-5.1
    PROMPT: |
      Review this pull request (read-only mode, DO NOT modify any code):
    USE_GITHUB_TOKEN: "true"
    GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
    ZHIPU_API_KEY: ${{ secrets.ZHIPU_API_KEY }}
```

More examples live in `examples/`.

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
- smoke-tests both actions through `uses: ./setup-opencode` and `uses: ./run-opencode`

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
5. Use `owner/repo/setup-opencode@v1` or `owner/repo/run-opencode@v1` from other repositories.

The initial release-notes template lives at `docs/releases/v1.0.0.md`.

## Limitations

- `args` is parsed as a space-delimited string, so keep complex text in environment variables like `PROMPT`
- the installer is external, so cache invalidation uses `cache-key` instead of a guaranteed version pin
- first version is optimized for GitHub-hosted or Linux self-hosted runners
