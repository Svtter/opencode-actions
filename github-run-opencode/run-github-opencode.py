#!/usr/bin/env python3
import atexit
import os
import re
import subprocess
import sys
import tempfile
from pathlib import Path

script_dir = Path(__file__).resolve().parent


def get_env(name: str, default: str = "") -> str:
    return os.environ.get(name, default)


def set_env(name: str, value: str) -> None:
    if value:
        os.environ[name] = value


def require_non_negative_integer(value: str, name: str) -> int:
    if not value.isdigit():
        print(f"{name} must be a non-negative integer, got {value}", file=sys.stderr)
        sys.exit(1)
    return int(value)


def supports_model_with_available_key(model: str) -> bool:
    if model.startswith("zhipuai") and "/" in model:
        return bool(os.environ.get("ZHIPU_API_KEY"))
    if model.startswith("opencode-go/"):
        return bool(os.environ.get("OPENCODE_API_KEY"))
    if model.startswith("deepseek") and "/" in model:
        return bool(os.environ.get("DEEPSEEK_API_KEY"))
    return True


def validate_regex(pattern: str, name: str) -> None:
    if not pattern:
        return
    try:
        re.compile(pattern)
    except re.error:
        print(f"{name} is not a valid extended regex: {pattern}", file=sys.stderr)
        sys.exit(1)


def parse_candidate_models(raw_list: str) -> list[str]:
    result: list[str] = []
    for item in raw_list.split(","):
        normalized = item.strip().strip(",")
        if normalized and normalized not in result:
            result.append(normalized)
    return result


def run_model(model: str, log_file: str, model_timeout: int, run_script: Path) -> int:
    env = os.environ.copy()
    env["MODEL"] = model

    if model_timeout > 0:
        cmd = ["timeout", "--foreground", f"{model_timeout}s", str(run_script)]
    else:
        cmd = [str(run_script)]

    result = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, env=env)

    with open(log_file, "wb") as f:
        f.write(result.stdout)

    # Replay captured output so it is visible in CI / terminal
    sys.stdout.buffer.write(result.stdout)
    sys.stdout.buffer.flush()

    return result.returncode


def run_single(run_script: Path, timeout_sec: int) -> int:
    if timeout_sec > 0:
        result = subprocess.run(
            ["timeout", "--foreground", f"{timeout_sec}s", str(run_script)]
        )
    else:
        result = subprocess.run([str(run_script)])
    return result.returncode


def main() -> int:
    timeout_seconds = require_non_negative_integer(
        get_env("GITHUB_RUN_OPENCODE_TIMEOUT_SECONDS", "600"),
        "GITHUB_RUN_OPENCODE_TIMEOUT_SECONDS",
    )
    fallback_models_input = get_env("GITHUB_RUN_OPENCODE_FALLBACK_MODELS", "")
    model_timeout_seconds = require_non_negative_integer(
        get_env("GITHUB_RUN_OPENCODE_MODEL_TIMEOUT_SECONDS", "0"),
        "GITHUB_RUN_OPENCODE_MODEL_TIMEOUT_SECONDS",
    )
    fallback_on_regex = get_env(
        "GITHUB_RUN_OPENCODE_FALLBACK_ON_REGEX",
        "timed out|timeout|deadline exceeded|context deadline exceeded|operation timed out|connection timed out",
    )

    # Core opencode env
    os.environ["OPENCODE_ARGS"] = "github run"
    set_env("OPENCODE_WORKING_DIRECTORY", get_env("GITHUB_RUN_OPENCODE_WORKING_DIRECTORY"))
    set_env("OPENCODE_ATTEMPTS", get_env("GITHUB_RUN_OPENCODE_ATTEMPTS", "3"))
    set_env("OPENCODE_RETRY_PROFILE", get_env("GITHUB_RUN_OPENCODE_RETRY_PROFILE", "github-network"))
    set_env("OPENCODE_RETRY_ON_REGEX", get_env("GITHUB_RUN_OPENCODE_RETRY_ON_REGEX"))
    set_env("OPENCODE_RETRY_DELAY_SECONDS", get_env("GITHUB_RUN_OPENCODE_RETRY_DELAY_SECONDS", "15"))

    # Model resolution (same order as original shell script)
    if get_env("GITHUB_RUN_OPENCODE_MODEL"):
        os.environ["MODEL"] = get_env("GITHUB_RUN_OPENCODE_MODEL")
    elif get_env("MODEL_NAME"):
        os.environ["MODEL"] = get_env("MODEL_NAME")
    else:
        os.environ["MODEL"] = "zhipuai-coding-plan/glm-5.1"

    set_env("PROMPT", get_env("GITHUB_RUN_OPENCODE_PROMPT"))
    set_env("USE_GITHUB_TOKEN", get_env("GITHUB_RUN_OPENCODE_USE_GITHUB_TOKEN"))
    set_env("GITHUB_TOKEN", get_env("GITHUB_RUN_OPENCODE_GITHUB_TOKEN"))
    set_env("ZHIPU_API_KEY", get_env("GITHUB_RUN_OPENCODE_ZHIPU_API_KEY"))
    set_env("OPENCODE_API_KEY", get_env("GITHUB_RUN_OPENCODE_OPENCODE_GO_API_KEY"))
    set_env("DEEPSEEK_API_KEY", get_env("GITHUB_RUN_OPENCODE_DEEPSEEK_API_KEY"))

    validate_regex(fallback_on_regex, "GITHUB_RUN_OPENCODE_FALLBACK_ON_REGEX")

    run_script = script_dir / ".." / "run-opencode" / "run-opencode.sh"

    # Build candidate list: resolved model first, then fallbacks
    candidate_models: list[str] = []
    model = os.environ["MODEL"]
    if model:
        candidate_models.append(model)
    candidate_models.extend(parse_candidate_models(fallback_models_input))

    temp_files: list[str] = []

    def cleanup() -> None:
        for f in temp_files:
            try:
                os.unlink(f)
            except FileNotFoundError:
                pass

    atexit.register(cleanup)

    if not candidate_models:
        return run_single(run_script, timeout_seconds)

    # API key filtering
    eligible_models: list[str] = []
    for m in candidate_models:
        if supports_model_with_available_key(m):
            eligible_models.append(m)
        else:
            print(
                f"Skipping fallback model {m} because its provider key is unavailable",
                file=sys.stderr,
            )

    if not eligible_models:
        print("No eligible models available after API key filtering", file=sys.stderr)
        return 1

    if len(eligible_models) == 1:
        os.environ["MODEL"] = eligible_models[0]
        return run_single(run_script, timeout_seconds)

    # Fallback loop
    for index, m in enumerate(eligible_models):
        fd, log_file = tempfile.mkstemp()
        os.close(fd)
        temp_files.append(log_file)

        status = run_model(m, log_file, model_timeout_seconds, run_script)

        if status == 0:
            return 0

        is_last = index == len(eligible_models) - 1

        if status == 124:
            print(
                f"OpenCode model {m} timed out after {model_timeout_seconds}s",
                file=sys.stderr,
            )
            if is_last:
                return status
            continue

        with open(log_file, "r", encoding="utf-8", errors="replace") as f:
            content = f.read()

        if fallback_on_regex and re.search(fallback_on_regex, content, re.IGNORECASE):
            print(
                f"OpenCode model {m} matched fallback regex, trying next candidate",
                file=sys.stderr,
            )
            if is_last:
                return status
            continue

        return status

    return 1


if __name__ == "__main__":
    sys.exit(main())
