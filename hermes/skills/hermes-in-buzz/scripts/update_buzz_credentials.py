#!/usr/bin/env python3
"""Secure, cross-platform Buzz credential setup for Hermes Agent.

Secrets are entered with getpass and never accepted in argv. The owner key is
used only in memory and is never written to disk.
"""

from __future__ import annotations

import argparse
import getpass
import json
import os
from pathlib import Path
import re
import stat
import subprocess
import sys
import tempfile

KEY_RE = re.compile(r"^(?:nsec1[023456789acdefghjklmnpqrstuvwxyz]+|[0-9a-fA-F]{64})$")
PUB_RE = re.compile(r"^[0-9a-fA-F]{64}$")
ASSIGN_RE = re.compile(r"^([A-Za-z_][A-Za-z0-9_]*)=(.*)$")


def hermes_home(value: str | None) -> Path:
    raw = value or os.environ.get("HERMES_HOME")
    return Path(raw).expanduser().resolve() if raw else (Path.home() / ".hermes").resolve()


def env_path(home: Path) -> Path:
    return home / ".env"


def parse_env(path: Path) -> dict[str, str]:
    result: dict[str, str] = {}
    if not path.exists():
        return result
    for raw in path.read_text(encoding="utf-8").splitlines():
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        match = ASSIGN_RE.match(line)
        if not match:
            continue
        key, value = match.groups()
        value = value.strip()
        if len(value) >= 2 and value[0] == value[-1] and value[0] in "'\"":
            value = value[1:-1]
        result[key] = value
    return result


def atomic_set(path: Path, key: str, value: str) -> None:
    if "\n" in value or "\r" in value:
        raise ValueError("credential value must be one line")
    path.parent.mkdir(parents=True, exist_ok=True)
    lines = path.read_text(encoding="utf-8").splitlines() if path.exists() else []
    replacement = f"{key}={value}"
    output: list[str] = []
    replaced = False
    for line in lines:
        match = ASSIGN_RE.match(line.strip())
        if match and match.group(1) == key:
            if not replaced:
                output.append(replacement)
                replaced = True
            continue
        output.append(line)
    if not replaced:
        output.append(replacement)
    content = "\n".join(output).rstrip("\n") + "\n"
    old_mode = stat.S_IMODE(path.stat().st_mode) if path.exists() else 0o600
    fd, temporary = tempfile.mkstemp(prefix=".env.", dir=str(path.parent), text=True)
    try:
        with os.fdopen(fd, "w", encoding="utf-8", newline="\n") as handle:
            handle.write(content)
            handle.flush()
            os.fsync(handle.fileno())
        try:
            os.chmod(temporary, old_mode & 0o600 or 0o600)
        except OSError:
            pass
        os.replace(temporary, path)
        try:
            os.chmod(path, 0o600)
        except OSError:
            pass
    finally:
        try:
            os.unlink(temporary)
        except FileNotFoundError:
            pass


def run_helper(helper: Path, command: list[str], secret: str) -> str:
    if not helper.is_file():
        raise SystemExit(f"credential helper not found: {helper}")
    completed = subprocess.run(
        [str(helper), *command],
        input=secret + "\n",
        text=True,
        capture_output=True,
        check=False,
    )
    if completed.returncode:
        message = completed.stderr.strip() or "credential helper failed"
        raise SystemExit(message)
    return completed.stdout.strip()


def set_agent_key(args: argparse.Namespace) -> None:
    first = getpass.getpass("Buzz agent nsec/private key: ").strip()
    second = getpass.getpass("Confirm Buzz agent key: ").strip()
    if first != second:
        raise SystemExit("keys did not match")
    if not KEY_RE.fullmatch(first):
        raise SystemExit("invalid agent key format; expected nsec or 64 hex characters")
    path = env_path(hermes_home(args.hermes_home))
    atomic_set(path, "BUZZ_PRIVATE_KEY", first)
    first = second = ""
    print(f"Stored BUZZ_PRIVATE_KEY securely in {path}")


def show_public(args: argparse.Namespace) -> None:
    home = hermes_home(args.hermes_home)
    values = parse_env(env_path(home))
    secret = values.get("BUZZ_PRIVATE_KEY", "")
    if not secret:
        raise SystemExit("BUZZ_PRIVATE_KEY is not configured")
    output = run_helper(Path(args.helper).expanduser().resolve(), ["public"], secret)
    secret = ""
    fields = dict(line.split("=", 1) for line in output.splitlines() if "=" in line)
    if not PUB_RE.fullmatch(fields.get("hex", "")) or not fields.get("npub", "").startswith("npub1"):
        raise SystemExit("credential helper returned malformed public identity")
    print(f"hex={fields['hex']}")
    print(f"npub={fields['npub']}")


def set_auth_tag(args: argparse.Namespace) -> None:
    if not PUB_RE.fullmatch(args.agent_pubkey):
        raise SystemExit("--agent-pubkey must be 64 hexadecimal characters")
    owner = getpass.getpass("Buzz human/owner nsec (not stored): ").strip()
    if not KEY_RE.fullmatch(owner):
        raise SystemExit("invalid owner key format")
    raw = run_helper(
        Path(args.helper).expanduser().resolve(),
        ["auth-tag", args.agent_pubkey.lower(), args.conditions],
        owner,
    )
    owner = ""
    try:
        tag = json.loads(raw)
    except json.JSONDecodeError as exc:
        raise SystemExit(f"helper returned invalid auth-tag JSON: {exc}") from exc
    if not (isinstance(tag, list) and len(tag) == 4 and all(isinstance(v, str) for v in tag) and tag[0] == "auth"):
        raise SystemExit("helper returned an invalid NIP-OA four-string auth tag")
    compact = json.dumps(tag, separators=(",", ":"), ensure_ascii=True)
    path = env_path(hermes_home(args.hermes_home))
    atomic_set(path, "BUZZ_AUTH_TAG", compact)
    print(f"Stored BUZZ_AUTH_TAG securely in {path}; owner key was not stored")


def probe(args: argparse.Namespace) -> None:
    home = hermes_home(args.hermes_home)
    values = parse_env(env_path(home))
    child = os.environ.copy()
    for key, value in values.items():
        if key.startswith("BUZZ_"):
            child[key] = value
    child["BUZZ_RELAY_URL"] = args.relay
    command = [str(Path(args.buzz).expanduser().resolve()), "channels", "list"]
    completed = subprocess.run(command, env=child, text=True, capture_output=True, check=False)
    if completed.stdout:
        print(completed.stdout, end="")
    if completed.returncode:
        if completed.stderr:
            print(completed.stderr, file=sys.stderr, end="")
        raise SystemExit(completed.returncode)


def parser() -> argparse.ArgumentParser:
    root = argparse.ArgumentParser(description=__doc__)
    sub = root.add_subparsers(dest="command", required=True)

    key = sub.add_parser("set-agent-key", help="securely store the dedicated agent key")
    key.add_argument("--hermes-home")
    key.set_defaults(func=set_agent_key)

    public = sub.add_parser("public", help="print only the configured agent's public identity")
    public.add_argument("--hermes-home")
    public.add_argument("--helper", required=True)
    public.set_defaults(func=show_public)

    auth = sub.add_parser("set-auth-tag", help="generate and store NIP-OA owner attestation")
    auth.add_argument("--hermes-home")
    auth.add_argument("--helper", required=True)
    auth.add_argument("--agent-pubkey", required=True)
    auth.add_argument("--conditions", default="")
    auth.set_defaults(func=set_auth_tag)

    check = sub.add_parser("probe", help="run Buzz channel discovery with exact dotenv values")
    check.add_argument("--hermes-home")
    check.add_argument("--buzz", required=True)
    check.add_argument("--relay", required=True)
    check.set_defaults(func=probe)
    return root


def main() -> None:
    args = parser().parse_args()
    args.func(args)


if __name__ == "__main__":
    main()
