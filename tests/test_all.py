#!/usr/bin/env python3
"""Unified Python test suite for opencode-actions."""

import http.server
import os
import re
import shutil
import socket
import socketserver
import subprocess
import sys
import tempfile
import threading
import time
import unittest
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
FIXTURES_DIR = REPO_ROOT / "tests" / "fixtures"


def pick_port() -> int:
    sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    sock.bind(("127.0.0.1", 0))
    port = sock.getsockname()[1]
    sock.close()
    return port


class FixtureServer:
    """Simple HTTP server for test fixtures, runs in a background thread."""

    def __init__(self, directory: Path):
        self.directory = directory
        self.port = pick_port()
        self.server = None
        self.thread = None

    def start(self) -> None:
        handler = lambda *args, **kwargs: http.server.SimpleHTTPRequestHandler(
            *args, directory=str(self.directory), **kwargs
        )
        self.server = socketserver.TCPServer(("127.0.0.1", self.port), handler)
        self.thread = threading.Thread(target=self.server.serve_forever, daemon=True)
        self.thread.start()
        time.sleep(0.3)  # give server time to start

    def stop(self) -> None:
        if self.server:
            self.server.shutdown()
            self.server.server_close()

    def url(self, path: str) -> str:
        return f"http://127.0.0.1:{self.port}/{path}"


class TestSetupOpencode(unittest.TestCase):
    """Tests for setup-opencode/install-opencode.sh"""

    @classmethod
    def setUpClass(cls):
        cls.server = FixtureServer(FIXTURES_DIR)
        cls.server.start()

    @classmethod
    def tearDownClass(cls):
        cls.server.stop()

    def setUp(self):
        self.work_dir = Path(tempfile.mkdtemp())
        self.env = os.environ.copy()
        self.env["OPENCODE_INSTALL_URL"] = self.server.url("fake-installer.sh")
        self.env["OPENCODE_INSTALL_ATTEMPTS"] = "1"
        self.env["OPENCODE_ALLOW_PREINSTALLED"] = "false"
        self.env["PATH"] = "/usr/bin:/bin"
        # Clear vars that might leak from outer env (but preserve FAKE_* for installer)
        for key in [
            "OPENCODE_INSTALL_DIR",
            "XDG_CACHE_HOME",
            "HOME",
            "OPENCODE_MIN_VERSION",
        ]:
            self.env.pop(key, None)

    def tearDown(self):
        shutil.rmtree(self.work_dir, ignore_errors=True)
        for key in ["FAKE_OPENCODE_VERSION", "FAKE_INSTALL_TARGET"]:
            os.environ.pop(key, None)

    def run_install(self, case_dir: Path, **extra_env) -> subprocess.CompletedProcess:
        env = self.env.copy()
        env["HOME"] = str(case_dir / "home")
        env["OPENCODE_INSTALL_DIR"] = str(case_dir / "bin")
        env["XDG_CACHE_HOME"] = str(case_dir / "cache")
        # Propagate FAKE_* vars that may have been set on os.environ after setUp
        for key in ("FAKE_OPENCODE_VERSION", "FAKE_INSTALL_TARGET"):
            if key in os.environ:
                env[key] = os.environ[key]
        env.update(extra_env)
        result = subprocess.run(
            [str(REPO_ROOT / "setup-opencode" / "install-opencode.sh")],
            capture_output=True,
            text=True,
            env=env,
        )
        return result

    def test_install_to_dir(self):
        """Installer should place binary in OPENCODE_INSTALL_DIR."""
        case = self.work_dir / "case-one"
        os.environ["FAKE_OPENCODE_VERSION"] = "1.2.3-test"
        result = self.run_install(case, FAKE_INSTALL_TARGET="install-dir")
        self.assertEqual(result.returncode, 0, result.stderr)

        binary = case / "bin" / "opencode"
        self.assertTrue(binary.exists(), "expected installed binary")
        self.assertTrue(os.access(binary, os.X_OK), "expected executable")

        version = subprocess.run([str(binary), "--version"], capture_output=True, text=True)
        self.assertEqual(version.stdout.strip(), "1.2.3-test")

    def test_preinstalled_not_used(self):
        """When allow-preinstalled=false, existing binary on PATH should be ignored."""
        case = self.work_dir / "case-two"
        fake_path = case / "path"
        fake_path.mkdir(parents=True)
        fake_bin = fake_path / "opencode"
        fake_bin.write_text("#!/bin/bash\nprintf 'preinstalled-version\\n'\n")
        fake_bin.chmod(0o755)

        os.environ["FAKE_OPENCODE_VERSION"] = "2.3.4-installed"
        env = self.env.copy()
        env["PATH"] = f"{fake_path}:/usr/bin:/bin"
        result = self.run_install(case, FAKE_INSTALL_TARGET="install-dir", PATH=env["PATH"])
        self.assertEqual(result.returncode, 0, result.stderr)

        version = subprocess.run(
            [str(case / "bin" / "opencode"), "--version"], capture_output=True, text=True
        )
        self.assertEqual(version.stdout.strip(), "2.3.4-installed")

    def test_preinstalled_opt_in(self):
        """When allow-preinstalled=true, existing binary should be reused."""
        case = self.work_dir / "case-two-opt-in"
        fake_path = case / "path"
        fake_path.mkdir(parents=True)
        fake_bin = fake_path / "opencode"
        fake_bin.write_text("#!/bin/bash\nprintf 'preinstalled-version\\n'\n")
        fake_bin.chmod(0o755)

        os.environ["FAKE_OPENCODE_VERSION"] = "should-not-install"
        env = self.env.copy()
        env["PATH"] = f"{fake_path}:/usr/bin:/bin"
        result = self.run_install(
            case,
            FAKE_INSTALL_TARGET="install-dir",
            OPENCODE_ALLOW_PREINSTALLED="true",
            PATH=env["PATH"],
        )
        self.assertEqual(result.returncode, 0, result.stderr)

        version = subprocess.run(
            [str(case / "bin" / "opencode"), "--version"], capture_output=True, text=True
        )
        self.assertEqual(version.stdout.strip(), "preinstalled-version")

    def test_install_to_home_bin(self):
        """FAKE_INSTALL_TARGET=home-bin should install to ~/.opencode/bin."""
        case = self.work_dir / "case-three"
        os.environ["FAKE_OPENCODE_VERSION"] = "4.5.6-home"
        result = self.run_install(case, FAKE_INSTALL_TARGET="home-bin")
        self.assertEqual(result.returncode, 0, result.stderr)

        # install-opencode.sh copies from ~/.opencode/bin to OPENCODE_INSTALL_DIR
        binary = case / "bin" / "opencode"
        self.assertTrue(binary.exists(), "expected fallback-installed binary")

        version = subprocess.run([str(binary), "--version"], capture_output=True, text=True)
        self.assertEqual(version.stdout.strip(), "4.5.6-home")

    def test_recover_broken_cache(self):
        """Broken cached binary should be reinstalled."""
        case = self.work_dir / "case-four"
        broken = case / "bin" / "opencode"
        broken.parent.mkdir(parents=True)
        broken.write_text("#!/bin/bash\nprintf 'broken cached binary\\n' >&2; exit 99\n")
        broken.chmod(0o755)

        os.environ["FAKE_OPENCODE_VERSION"] = "7.8.9-recovered"
        result = self.run_install(case, FAKE_INSTALL_TARGET="install-dir")
        self.assertEqual(result.returncode, 0, result.stderr)

        version = subprocess.run([str(case / "bin" / "opencode"), "--version"], capture_output=True, text=True)
        self.assertEqual(version.stdout.strip(), "7.8.9-recovered")

    def test_attempts_validation(self):
        """OPENCODE_INSTALL_ATTEMPTS=0 should fail validation."""
        case = self.work_dir / "case-five"
        fake_path = case / "path"
        fake_path.mkdir(parents=True)
        fake_bin = fake_path / "opencode"
        fake_bin.write_text("#!/bin/bash\nprintf 'unexpected-preinstalled\\n'\n")
        fake_bin.chmod(0o755)

        os.environ["FAKE_OPENCODE_VERSION"] = "should-fail"
        env = self.env.copy()
        env["PATH"] = f"{fake_path}:/usr/bin:/bin"
        result = self.run_install(
            case, FAKE_INSTALL_TARGET="install-dir", OPENCODE_INSTALL_ATTEMPTS="0", PATH=env["PATH"]
        )
        self.assertNotEqual(result.returncode, 0, "expected install-attempts=0 to fail validation")

    def test_version_upgrade(self):
        """Cached binary below min version should be reinstalled."""
        case = self.work_dir / "case-six"
        cached = case / "bin" / "opencode"
        cached.parent.mkdir(parents=True)
        cached.write_text("#!/bin/bash\nif [[ \"$1\" == '--version' ]]; then printf '1.0.0\\n'; exit 0; fi\n")
        cached.chmod(0o755)

        os.environ["FAKE_OPENCODE_VERSION"] = "2.0.0-upgraded"
        result = self.run_install(
            case, FAKE_INSTALL_TARGET="install-dir", OPENCODE_INSTALL_ATTEMPTS="3", OPENCODE_MIN_VERSION="1.4.5"
        )
        self.assertEqual(result.returncode, 0, result.stderr)

        version = subprocess.run([str(cached), "--version"], capture_output=True, text=True)
        self.assertEqual(version.stdout.strip(), "2.0.0-upgraded")

    def test_cached_version_ok(self):
        """Cached binary meeting min version should be reused."""
        case = self.work_dir / "case-seven"
        cached = case / "bin" / "opencode"
        cached.parent.mkdir(parents=True)
        cached.write_text("#!/bin/bash\nif [[ \"$1\" == '--version' ]]; then printf '2.0.0\\n'; exit 0; fi\n")
        cached.chmod(0o755)

        os.environ["FAKE_OPENCODE_VERSION"] = "should-not-install"
        result = self.run_install(
            case, FAKE_INSTALL_TARGET="install-dir", OPENCODE_MIN_VERSION="1.4.5"
        )
        self.assertEqual(result.returncode, 0, result.stderr)

        version = subprocess.run([str(cached), "--version"], capture_output=True, text=True)
        self.assertEqual(version.stdout.strip(), "2.0.0")

    def test_version_check_disabled(self):
        """Empty OPENCODE_MIN_VERSION should disable version checking."""
        case = self.work_dir / "case-eight"
        cached = case / "bin" / "opencode"
        cached.parent.mkdir(parents=True)
        cached.write_text("#!/bin/bash\nif [[ \"$1\" == '--version' ]]; then printf '0.1.0\\n'; exit 0; fi\n")
        cached.chmod(0o755)

        os.environ["FAKE_OPENCODE_VERSION"] = "should-not-install"
        result = self.run_install(case, FAKE_INSTALL_TARGET="install-dir", OPENCODE_MIN_VERSION="")
        self.assertEqual(result.returncode, 0, result.stderr)

        version = subprocess.run([str(cached), "--version"], capture_output=True, text=True)
        self.assertEqual(version.stdout.strip(), "0.1.0")

    def test_prerelease_upgrade(self):
        """Prerelease cached version below min should upgrade."""
        case = self.work_dir / "case-nine"
        cached = case / "bin" / "opencode"
        cached.parent.mkdir(parents=True)
        cached.write_text("#!/bin/bash\nif [[ \"$1\" == '--version' ]]; then printf '1.5.0-beta.1\\n'; exit 0; fi\n")
        cached.chmod(0o755)

        os.environ["FAKE_OPENCODE_VERSION"] = "1.5.0"
        result = self.run_install(
            case, FAKE_INSTALL_TARGET="install-dir", OPENCODE_MIN_VERSION="1.5.0"
        )
        self.assertEqual(result.returncode, 0, result.stderr)

        version = subprocess.run([str(cached), "--version"], capture_output=True, text=True)
        self.assertEqual(version.stdout.strip(), "1.5.0")

    def test_invalid_min_version(self):
        """Invalid OPENCODE_MIN_VERSION should fail."""
        case = self.work_dir / "case-ten"
        cached = case / "bin" / "opencode"
        cached.parent.mkdir(parents=True)
        cached.write_text("#!/bin/bash\nif [[ \"$1\" == '--version' ]]; then printf '1.5.0\\n'; exit 0; fi\n")
        cached.chmod(0o755)

        os.environ["FAKE_OPENCODE_VERSION"] = "1.5.0"
        result = self.run_install(
            case, FAKE_INSTALL_TARGET="install-dir", OPENCODE_MIN_VERSION="not-a-semver"
        )
        self.assertNotEqual(result.returncode, 0, "expected invalid minimum version to fail")

    def test_preinstalled_upgrade(self):
        """Outdated preinstalled binary below min version should upgrade."""
        case = self.work_dir / "case-eleven"
        fake_path = case / "path"
        fake_path.mkdir(parents=True)
        fake_bin = fake_path / "opencode"
        fake_bin.write_text("#!/bin/bash\nif [[ \"$1\" == '--version' ]]; then printf '1.0.0\\n'; exit 0; fi\n")
        fake_bin.chmod(0o755)

        os.environ["FAKE_OPENCODE_VERSION"] = "1.6.0"
        env = self.env.copy()
        env["PATH"] = f"{fake_path}:/usr/bin:/bin"
        result = self.run_install(
            case,
            FAKE_INSTALL_TARGET="install-dir",
            OPENCODE_ALLOW_PREINSTALLED="true",
            OPENCODE_MIN_VERSION="1.5.0",
            PATH=env["PATH"],
        )
        self.assertEqual(result.returncode, 0, result.stderr)

        version = subprocess.run([str(case / "bin" / "opencode"), "--version"], capture_output=True, text=True)
        self.assertEqual(version.stdout.strip(), "1.6.0")

    def test_install_below_min_version(self):
        """Fresh install below min version should fail."""
        case = self.work_dir / "case-twelve"
        cached = case / "bin" / "opencode"
        cached.parent.mkdir(parents=True)
        cached.write_text("#!/bin/bash\nif [[ \"$1\" == '--version' ]]; then printf '1.0.0\\n'; exit 0; fi\n")
        cached.chmod(0o755)

        os.environ["FAKE_OPENCODE_VERSION"] = "1.4.9"
        result = self.run_install(
            case, FAKE_INSTALL_TARGET="install-dir", OPENCODE_MIN_VERSION="1.5.0"
        )
        self.assertNotEqual(result.returncode, 0, "expected install below min version to fail")


class TestRunOpencode(unittest.TestCase):
    """Tests for run-opencode/run-opencode.sh"""

    def setUp(self):
        self.work_dir = Path(tempfile.mkdtemp())
        self.attempt_file = self.work_dir / "attempts"
        self.fake_opencode = self.work_dir / "opencode"
        self.fake_opencode.write_text(
            '#!/bin/bash\n'
            'attempt_file="${FAKE_OPENCODE_ATTEMPT_FILE:?}"\n'
            'attempt=0\n'
            'if [[ -f "$attempt_file" ]]; then\n'
            '  attempt=$(<"$attempt_file")\n'
            'fi\n'
            'attempt=$((attempt + 1))\n'
            'printf "%s" "$attempt" >"$attempt_file"\n'
            'if (( attempt < 3 )); then\n'
            '  printf "Failed to connect to github.com port 443\\n" >&2\n'
            '  exit 42\n'
            'fi\n'
            'printf "success on attempt %s\\n" "$attempt"\n'
        )
        self.fake_opencode.chmod(0o755)

        self.env = os.environ.copy()
        self.env["PATH"] = f"{self.work_dir}:{os.environ.get('PATH', '')}"
        self.env["FAKE_OPENCODE_ATTEMPT_FILE"] = str(self.attempt_file)
        self.env["OPENCODE_ARGS"] = "github run"
        self.env["OPENCODE_ATTEMPTS"] = "3"
        self.env["OPENCODE_RETRY_DELAY_SECONDS"] = "0"
        self.env["OPENCODE_RETRY_PROFILE"] = ""

    def tearDown(self):
        shutil.rmtree(self.work_dir, ignore_errors=True)

    def run_opencode(self, **extra_env) -> subprocess.CompletedProcess:
        env = self.env.copy()
        env.update(extra_env)
        return subprocess.run(
            [str(REPO_ROOT / "run-opencode" / "run-opencode.sh")],
            capture_output=True,
            text=True,
            env=env,
        )

    def test_retry_with_regex(self):
        """Should retry when output matches retry-on-regex."""
        result = self.run_opencode(
            OPENCODE_RETRY_ON_REGEX="Failed to connect to github\\.com port 443"
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("success on attempt 3", result.stdout)

        attempts = self.attempt_file.read_text().strip()
        self.assertEqual(attempts, "3")

    def test_retry_with_profile(self):
        """Should retry with built-in github-network profile."""
        if self.attempt_file.exists():
            self.attempt_file.unlink()
        result = self.run_opencode(
            OPENCODE_RETRY_ON_REGEX="",
            OPENCODE_RETRY_PROFILE="github-network",
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("success on attempt 3", result.stdout)

        attempts = self.attempt_file.read_text().strip()
        self.assertEqual(attempts, "3")

    def test_attempts_validation(self):
        """OPENCODE_ATTEMPTS=0 should fail validation."""
        result = self.run_opencode(OPENCODE_ATTEMPTS="0")
        self.assertNotEqual(result.returncode, 0, "expected attempts=0 to fail validation")


class TestGithubRunOpencode(unittest.TestCase):
    """Tests for github-run-opencode/run-github-opencode.py"""

    @classmethod
    def setUpClass(cls):
        cls.server = FixtureServer(FIXTURES_DIR)
        cls.server.start()

    @classmethod
    def tearDownClass(cls):
        cls.server.stop()

    def setUp(self):
        self.work_dir = Path(tempfile.mkdtemp())
        self.env = os.environ.copy()

        # Install fake opencode
        install_env = self.env.copy()
        install_env["HOME"] = str(self.work_dir / "home")
        install_env["OPENCODE_INSTALL_URL"] = self.server.url("fake-installer.sh")
        install_env["OPENCODE_INSTALL_DIR"] = str(self.work_dir / "bin")
        install_env["XDG_CACHE_HOME"] = str(self.work_dir / "cache")
        install_env["OPENCODE_INSTALL_ATTEMPTS"] = "1"
        install_env["OPENCODE_ALLOW_PREINSTALLED"] = "false"
        install_env["FAKE_OPENCODE_VERSION"] = "9.9.9-wrapper"
        install_env["PATH"] = "/usr/bin:/bin"

        result = subprocess.run(
            [str(REPO_ROOT / "setup-opencode" / "install-opencode.sh")],
            capture_output=True,
            text=True,
            env=install_env,
        )
        self.assertEqual(result.returncode, 0, f"install failed: {result.stderr}")

        # Create fake timeout that records duration
        self.fake_bin_dir = self.work_dir / "fake-bin"
        self.fake_bin_dir.mkdir()
        real_timeout = shutil.which("timeout")
        fake_timeout = self.fake_bin_dir / "timeout"
        fake_timeout.write_text(
            '#!/bin/bash\n'
            'foreground=""\n'
            'if [[ "${1:-}" == "--foreground" ]]; then\n'
            '  shift\n'
            '  foreground="--foreground"\n'
            'fi\n'
            'duration="$1"\n'
            'shift\n'
            'printf "TIMEOUT_DURATION=%s\\n" "$duration"\n'
            f'exec "{real_timeout}" $foreground "$duration" "$@"\n'
        )
        fake_timeout.chmod(0o755)

        self.env["PATH"] = f"{self.fake_bin_dir}:{self.work_dir / 'bin'}:/usr/bin:/bin"

    def tearDown(self):
        shutil.rmtree(self.work_dir, ignore_errors=True)
        for key in [
            "GITHUB_RUN_OPENCODE_MODEL",
            "GITHUB_RUN_OPENCODE_PROMPT",
            "GITHUB_RUN_OPENCODE_USE_GITHUB_TOKEN",
            "GITHUB_RUN_OPENCODE_GITHUB_TOKEN",
            "GITHUB_RUN_OPENCODE_ZHIPU_API_KEY",
            "GITHUB_RUN_OPENCODE_OPENCODE_GO_API_KEY",
            "GITHUB_RUN_OPENCODE_ATTEMPTS",
            "GITHUB_RUN_OPENCODE_RETRY_PROFILE",
            "GITHUB_RUN_OPENCODE_FALLBACK_MODELS",
            "GITHUB_RUN_OPENCODE_MODEL_TIMEOUT_SECONDS",
            "GITHUB_RUN_OPENCODE_FALLBACK_ON_REGEX",
            "GITHUB_RUN_OPENCODE_TIMEOUT_SECONDS",
            "FAKE_OPENCODE_TIMEOUT_MODELS",
            "FAKE_OPENCODE_TIMEOUT_SLEEP_SECONDS",
            "FAKE_OPENCODE_ERROR_MODELS",
            "MODEL_NAME",
        ]:
            os.environ.pop(key, None)

    def reset_env(self):
        for key in [
            "GITHUB_RUN_OPENCODE_FALLBACK_MODELS",
            "GITHUB_RUN_OPENCODE_MODEL_TIMEOUT_SECONDS",
            "GITHUB_RUN_OPENCODE_FALLBACK_ON_REGEX",
            "GITHUB_RUN_OPENCODE_TIMEOUT_SECONDS",
            "FAKE_OPENCODE_TIMEOUT_MODELS",
            "FAKE_OPENCODE_TIMEOUT_SLEEP_SECONDS",
            "FAKE_OPENCODE_ERROR_MODELS",
            "MODEL_NAME",
        ]:
            self.env.pop(key, None)

        self.env["GITHUB_RUN_OPENCODE_MODEL"] = "wrapper-model"
        self.env["GITHUB_RUN_OPENCODE_PROMPT"] = "review prompt"
        self.env["GITHUB_RUN_OPENCODE_USE_GITHUB_TOKEN"] = "true"
        self.env["GITHUB_RUN_OPENCODE_GITHUB_TOKEN"] = "gh-token"
        self.env["GITHUB_RUN_OPENCODE_ZHIPU_API_KEY"] = "zhipu-token"
        self.env["GITHUB_RUN_OPENCODE_OPENCODE_GO_API_KEY"] = "go-token"
        self.env["GITHUB_RUN_OPENCODE_ATTEMPTS"] = "1"
        self.env["GITHUB_RUN_OPENCODE_RETRY_PROFILE"] = "github-network"

    def run_wrapper(self, **extra_env) -> subprocess.CompletedProcess:
        env = self.env.copy()
        env.update(extra_env)
        return subprocess.run(
            ["python3", str(REPO_ROOT / "github-run-opencode" / "run-github-opencode.py")],
            capture_output=True,
            text=True,
            env=env,
        )

    def test_single_model_default(self):
        """Default single-model path should work with global timeout."""
        self.reset_env()
        result = self.run_wrapper()
        self.assertEqual(result.returncode, 0, f"stderr: {result.stderr}")
        self.assertIn("fake opencode github run", result.stdout)
        self.assertIn("MODEL=wrapper-model", result.stdout)
        self.assertIn("PROMPT=review prompt", result.stdout)
        self.assertIn("USE_GITHUB_TOKEN=true", result.stdout)
        self.assertIn("GITHUB_TOKEN=gh-token", result.stdout)
        self.assertIn("ZHIPU_API_KEY=zhipu-token", result.stdout)
        self.assertIn("OPENCODE_API_KEY=go-token", result.stdout)
        self.assertIn("TIMEOUT_DURATION=600s", result.stdout)

    def test_single_model_timeout_override(self):
        """Global timeout should be overrideable."""
        self.reset_env()
        result = self.run_wrapper(GITHUB_RUN_OPENCODE_TIMEOUT_SECONDS="7")
        self.assertEqual(result.returncode, 0, f"stderr: {result.stderr}")
        self.assertIn("TIMEOUT_DURATION=7s", result.stdout)

    def test_fallback_on_timeout(self):
        """Should fallback to next model when current times out."""
        self.reset_env()
        result = self.run_wrapper(
            GITHUB_RUN_OPENCODE_MODEL="zhipuai-coding-plan/glm-5",
            GITHUB_RUN_OPENCODE_FALLBACK_MODELS="opencode-go/gemini-2.5-pro",
            GITHUB_RUN_OPENCODE_MODEL_TIMEOUT_SECONDS="1",
            FAKE_OPENCODE_TIMEOUT_MODELS="zhipuai-coding-plan/glm-5",
            FAKE_OPENCODE_TIMEOUT_SLEEP_SECONDS="2",
        )
        self.assertEqual(result.returncode, 0, f"stderr: {result.stderr}")
        self.assertIn("MODEL=opencode-go/gemini-2.5-pro", result.stdout)
        self.assertIn("OpenCode model zhipuai-coding-plan/glm-5 timed out", result.stderr)

    def test_model_name_env(self):
        """MODEL_NAME env should be used when GITHUB_RUN_OPENCODE_MODEL is not set."""
        self.reset_env()
        self.env.pop("GITHUB_RUN_OPENCODE_MODEL", None)
        result = self.run_wrapper(MODEL_NAME="env-model-name")
        self.assertEqual(result.returncode, 0, f"stderr: {result.stderr}")
        self.assertIn("MODEL=env-model-name", result.stdout)

    def test_builtin_model_fallback(self):
        """Built-in default model should be used when nothing else is set."""
        self.reset_env()
        self.env.pop("GITHUB_RUN_OPENCODE_MODEL", None)
        result = self.run_wrapper()
        self.assertEqual(result.returncode, 0, f"stderr: {result.stderr}")
        self.assertIn("MODEL=zhipuai-coding-plan/glm-5.1", result.stdout)

    def test_fallback_on_regex(self):
        """Should fallback when output matches fallback-on-regex."""
        self.reset_env()
        result = self.run_wrapper(
            GITHUB_RUN_OPENCODE_MODEL="zhipuai-coding-plan/glm-5",
            GITHUB_RUN_OPENCODE_FALLBACK_MODELS="opencode-go/gemini-2.5-pro",
            GITHUB_RUN_OPENCODE_MODEL_TIMEOUT_SECONDS="5",
            GITHUB_RUN_OPENCODE_FALLBACK_ON_REGEX="deadline exceeded",
            FAKE_OPENCODE_ERROR_MODELS="zhipuai-coding-plan/glm-5",
        )
        self.assertEqual(result.returncode, 0, f"stderr: {result.stderr}")
        self.assertIn("MODEL=opencode-go/gemini-2.5-pro", result.stdout)
        self.assertIn("matched fallback regex", result.stderr)

    def test_api_key_filtering_skips_model(self):
        """Should skip models whose provider key is unavailable."""
        self.reset_env()
        self.env.pop("GITHUB_RUN_OPENCODE_ZHIPU_API_KEY", None)
        self.env.pop("ZHIPU_API_KEY", None)
        result = self.run_wrapper(
            GITHUB_RUN_OPENCODE_MODEL="zhipuai-coding-plan/glm-5",
            GITHUB_RUN_OPENCODE_FALLBACK_MODELS="opencode-go/gemini-2.5-pro",
        )
        self.assertEqual(result.returncode, 0, f"stderr: {result.stderr}")
        self.assertIn("MODEL=opencode-go/gemini-2.5-pro", result.stdout)

    def test_newline_delimited_fallback_models(self):
        """Should support newline-separated fallback-models."""
        self.reset_env()
        result = self.run_wrapper(
            GITHUB_RUN_OPENCODE_MODEL="wrapper-model",
            GITHUB_RUN_OPENCODE_FALLBACK_MODELS="opencode-go/gemini-2.5-pro\nzhipuai-coding-plan/glm-5.1",
            GITHUB_RUN_OPENCODE_MODEL_TIMEOUT_SECONDS="1",
            FAKE_OPENCODE_TIMEOUT_MODELS="wrapper-model",
            FAKE_OPENCODE_TIMEOUT_SLEEP_SECONDS="2",
        )
        self.assertEqual(result.returncode, 0, f"stderr: {result.stderr}")
        self.assertIn("MODEL=opencode-go/gemini-2.5-pro", result.stdout)

    def test_global_timeout_zero_disables_timeout(self):
        """timeout-seconds=0 should disable global timeout."""
        self.reset_env()
        result = self.run_wrapper(GITHUB_RUN_OPENCODE_TIMEOUT_SECONDS="0")
        self.assertEqual(result.returncode, 0, f"stderr: {result.stderr}")
        self.assertNotIn("TIMEOUT_DURATION", result.stdout)


class TestReviewAction(unittest.TestCase):
    """Tests for review action metadata."""

    def extract_prompt_default(self, action_file: Path) -> str:
        text = action_file.read_text()
        m = re.search(
            r"^  prompt:\s*\n    default:\s*\|\s*\n((?:(?<=\n)      .*\n)*)",
            text,
            re.MULTILINE,
        )
        if not m:
            return ""
        lines = m.group(1).splitlines()
        return "\n".join(line[6:] for line in lines) + "\n"

    def extract_field(self, action_file: Path, field: str) -> str:
        text = action_file.read_text()
        m = re.search(
            rf"^  {re.escape(field)}:\s*\n(?:    .*\n)*?    default:\s*(.+)$",
            text,
            re.MULTILINE,
        )
        if not m:
            return ""
        return m.group(1).strip()

    def has_input(self, action_file: Path, field: str) -> bool:
        text = action_file.read_text()
        return bool(re.search(rf"^  {re.escape(field)}:\s*$", text, re.MULTILINE))

    def test_prompt_defaults_consistent(self):
        github_run = REPO_ROOT / "github-run-opencode" / "action.yml"
        review = REPO_ROOT / "review" / "action.yml"
        github_run_prompt = self.extract_prompt_default(github_run)
        review_prompt = self.extract_prompt_default(review)
        # One may be empty; if both are non-empty they should match
        if github_run_prompt and review_prompt:
            self.assertEqual(
                github_run_prompt,
                review_prompt,
                "review/action.yml prompt default must match github-run-opencode/action.yml",
            )

    def test_review_model_default_empty(self):
        review = REPO_ROOT / "review" / "action.yml"
        self.assertEqual(self.extract_field(review, "model"), '""')

    def test_both_have_timeout_seconds(self):
        github_run = REPO_ROOT / "github-run-opencode" / "action.yml"
        review = REPO_ROOT / "review" / "action.yml"
        self.assertTrue(self.has_input(github_run, "timeout-seconds"))
        self.assertTrue(self.has_input(review, "timeout-seconds"))

    def test_timeout_defaults_are_600(self):
        github_run = REPO_ROOT / "github-run-opencode" / "action.yml"
        review = REPO_ROOT / "review" / "action.yml"
        self.assertEqual(self.extract_field(github_run, "timeout-seconds"), '"600"')
        self.assertEqual(self.extract_field(review, "timeout-seconds"), '"600"')


class TestDogfoodWorkflow(unittest.TestCase):
    """Tests for .github/workflows/review.yml dogfood checks."""

    def setUp(self):
        self.workflow_file = REPO_ROOT / ".github" / "workflows" / "review.yml"

    def test_workflow_exists(self):
        self.assertTrue(self.workflow_file.exists())

    def test_uses_review_v1(self):
        content = self.workflow_file.read_text()
        self.assertIn("uses: Svtter/opencode-actions/review@v1", content)

    def test_has_model_input(self):
        content = self.workflow_file.read_text()
        self.assertIn("model:", content)

    def test_skips_fork_prs(self):
        content = self.workflow_file.read_text()
        self.assertIn("github.event.pull_request.head.repo.full_name == github.repository", content)

    def test_wires_zhipu_key(self):
        content = self.workflow_file.read_text()
        self.assertIn("zhipu-api-key: ${{ secrets.ZHIPU_API_KEY }}", content)


if __name__ == "__main__":
    unittest.main(verbosity=2)
