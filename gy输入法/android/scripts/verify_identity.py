#!/usr/bin/env python3
"""GY Android identity contract gate.

Validates android/identity.lock against the actual project files. These fields are
an upgrade ABI: changing one requires an explicit, device-tested migration rather
than an ordinary in-place upgrade (discipline mirrors
macos/scripts/verify-input-source-contract.sh).

Also enforces the privacy gate: v0.1/v0.2 declare ZERO <uses-permission>
(including INTERNET). The BIND_INPUT_METHOD attribute on the IME <service> is the
standard signature-level IME guard held by the system, not a user permission.

Exit codes: 0 = valid, 1 = contract violation, 2 = missing files / lock parse error.
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
LOCK = ROOT / "identity.lock"
APP_GRADLE = ROOT / "app" / "build.gradle.kts"
MANIFEST = ROOT / "app" / "src" / "main" / "AndroidManifest.xml"
STRINGS = ROOT / "app" / "src" / "main" / "res" / "values" / "strings.xml"
METHOD_XML = ROOT / "app" / "src" / "main" / "res" / "xml" / "method.xml"
MAIN_SRC = ROOT / "app" / "src" / "main" / "kotlin"

violations: list[str] = []


def fail(message: str) -> None:
    violations.append(message)


def read(path: Path) -> str:
    if not path.is_file():
        print(f"missing required file: {path}", file=sys.stderr)
        sys.exit(2)
    return path.read_text(encoding="utf-8")


def load_lock() -> dict[str, str]:
    if not LOCK.is_file():
        print(f"identity lock not found: {LOCK}", file=sys.stderr)
        sys.exit(2)
    values: dict[str, str] = {}
    for lineno, raw in enumerate(LOCK.read_text(encoding="utf-8").splitlines(), 1):
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        if "=" not in line:
            print(f"identity.lock:{lineno}: not a key=value line: {raw!r}", file=sys.stderr)
            sys.exit(2)
        key, _, value = line.partition("=")
        values[key.strip()] = value.strip()
    for required in ("applicationId", "namespace", "imeServiceClass", "providerAuthoritiesPrefix", "brandDisplayName"):
        if required not in values:
            print(f"identity.lock: missing required key {required!r}", file=sys.stderr)
            sys.exit(2)
    return values


def require_equal(what: str, expected: str, actual: str) -> None:
    if actual != expected:
        fail(f"identity violation: {what} must remain {expected!r}, got {actual!r}")


def require_contains(what: str, needle: str, haystack: str, where: Path) -> None:
    if needle not in haystack:
        fail(f"identity violation: {what} must contain {needle!r} in {where}")


def main() -> int:
    lock = load_lock()
    app_id = lock["applicationId"]
    namespace = lock["namespace"]
    service_class = lock["imeServiceClass"]

    gradle = read(APP_GRADLE)
    require_contains("app/build.gradle.kts", f'applicationId = "{app_id}"', gradle, APP_GRADLE)
    require_contains("app/build.gradle.kts", f'namespace = "{namespace}"', gradle, APP_GRADLE)

    manifest = read(MANIFEST)

    # Privacy gate: zero permission declarations (the whole point of v0.1/v0.2).
    # Strip XML comments first — prose about permissions must not trip the gate.
    manifest_no_comments = re.sub(r"<!--.*?-->", "", manifest, flags=re.DOTALL)
    declared = re.findall(r"<uses-permission[^>]*>", manifest_no_comments)
    if declared:
        fail("privacy violation: AndroidManifest must declare zero <uses-permission> "
             f"(incl. INTERNET) for v0.1/v0.2, found: {declared}")

    simple_name = service_class.rsplit(".", 1)[-1]
    require_contains("IME service", f'android:name=".{simple_name}"', manifest, MANIFEST)
    require_contains("IME service guard", 'android:permission="android.permission.BIND_INPUT_METHOD"', manifest, MANIFEST)
    require_contains("IME metadata", 'android:name="android.view.im"', manifest, MANIFEST)

    strings = read(STRINGS)
    require_contains("brand display name", f'<string name="app_name">{lock["brandDisplayName"]}</string>', strings, STRINGS)

    method = read(METHOD_XML)
    require_contains("zh_CN subtype", 'android:imeSubtypeLocale="zh_CN"', method, METHOD_XML)
    require_contains("ascii-capable subtype", 'android:isAsciiCapable="true"', method, METHOD_XML)

    # Package directory and package declaration must match the namespace lock.
    package_dir = MAIN_SRC.joinpath(*namespace.split("."))
    if not package_dir.is_dir():
        fail(f"identity violation: kotlin package dir missing for namespace {namespace!r}: {package_dir}")

    service_file = package_dir / f"{simple_name}.kt"
    if not service_file.is_file():
        fail(f"identity violation: IME service source missing: {service_file}")
    else:
        service_src = service_file.read_text(encoding="utf-8")
        require_equal("service package declaration", f"package {namespace}", f"package {namespace}" if f"package {namespace}" in service_src else "<mismatch>")
        require_contains("IME service class", f"class {simple_name} : InputMethodService()", service_src, service_file)

    # Exactly one InputMethodService subclass: a second one would silently split
    # the input-method identity the system binds to (mirrors the IMKServer check).
    if MAIN_SRC.is_dir():
        hits = [
            p for p in MAIN_SRC.rglob("*.kt")
            if re.search(r":\s*InputMethodService\(\)", p.read_text(encoding="utf-8"))
        ]
        if len(hits) != 1:
            fail(f"identity violation: expected exactly one InputMethodService subclass, found {len(hits)}: {hits}")

    # applicationId ↔ provider authorities prefix family check.
    require_equal("provider authorities prefix", app_id + ".", lock["providerAuthoritiesPrefix"])

    if violations:
        for v in violations:
            print(v, file=sys.stderr)
        return 1

    print(f"Android identity contract is valid: {app_id} / {service_class}")
    print("Privacy gate passed: zero <uses-permission> declared.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
