#!/usr/bin/env python3
"""
ClearLedger fintech-focused DAST-style API tests (custom scenarios beyond ZAP).

Requires: Python 3.10+ and `requests` (pip install requests).
Base URL: BASE_URL env (default http://clearledger.local).
JWT_SECRET: required for jwt_none / jwt_expired tests (must match auth-service signing key).

Idempotency: each scenario uses unique disposable emails. There is no delete-user API;
leftover rows are minimal lab noise. Re-running the script does not require manual cleanup.
"""

from __future__ import annotations

import base64
import hashlib
import hmac
import json
import os
import sys
import time
import uuid
from typing import Any

import requests

BASE_URL = os.environ.get("BASE_URL", "http://clearledger.local").rstrip("/")
JWT_SECRET = os.environ.get("JWT_SECRET", "")


def _b64url(data: bytes) -> str:
    return base64.urlsafe_b64encode(data).rstrip(b"=").decode("ascii")


def _req(
    method: str,
    path: str,
    *,
    headers: dict[str, str] | None = None,
    json_body: Any = None,
) -> requests.Response:
    url = f"{BASE_URL}{path}"
    return requests.request(
        method,
        url,
        headers=headers or {},
        json=json_body,
        timeout=30,
    )


def _print_fail(name: str, req: str, resp: requests.Response | None, msg: str) -> None:
    print(f"\n[FAIL] {name}")
    print(f"  Reason: {msg}")
    print(f"  Request: {req}")
    if resp is not None:
        print(f"  HTTP: {resp.status_code}")
        print(f"  Body: {resp.text[:2000]}")


def _register_or_login(email: str, password: str) -> None:
    r = _req("POST", "/auth/register", json_body={"email": email, "password": password})
    if r.status_code not in (200, 201):
        if r.status_code == 409:
            return
        raise RuntimeError(f"register failed: {r.status_code} {r.text}")


def _login(email: str, password: str) -> tuple[str, str]:
    r = _req(
        "POST",
        "/auth/login",
        json_body={"email": email, "password": password},
    )
    if r.status_code != 200:
        raise RuntimeError(f"login failed: {r.status_code} {r.text}")
    data = r.json()
    return data["access_token"], data["user_id"]


def test_bola_transaction_access() -> tuple[bool, str]:
    """
    BOLA / IDOR: user B must not read user A's transaction by ID.
    Fintech impact: cross-customer data exposure violates confidentiality and PCI scoping.
    """
    pw = "FintechTestPass123!"
    em_a = f"dast-bola-a-{uuid.uuid4().hex[:8]}@clearledger.local"
    em_b = f"dast-bola-b-{uuid.uuid4().hex[:8]}@clearledger.local"
    _register_or_login(em_a, pw)
    _register_or_login(em_b, pw)
    tok_a, _ = _login(em_a, pw)
    tok_b, _ = _login(em_b, pw)
    r = _req(
        "POST",
        "/ledger/transactions",
        headers={"Authorization": f"Bearer {tok_a}"},
        json_body={"amount": 10.0, "direction": "credit", "description": "bola seed"},
    )
    if r.status_code != 201:
        _print_fail(
            "BOLA transaction access",
            f"POST {BASE_URL}/ledger/transactions",
            r,
            "expected 201 from A create tx",
        )
        return False, "create tx failed"
    tx_id = r.json()["id"]
    r2 = _req(
        "GET",
        f"/ledger/transactions/{tx_id}",
        headers={"Authorization": f"Bearer {tok_b}"},
    )
    if r2.status_code in (403, 404):
        return True, "BOLA transaction access control"
    _print_fail(
        "BOLA transaction access",
        f"GET {BASE_URL}/ledger/transactions/{tx_id} as B",
        r2,
        f"expected 403 or 404, got {r2.status_code}",
    )
    return False, "BOLA vulnerability: other user could read transaction"


def test_negative_amount_transaction() -> tuple[bool, str]:
    """
    Business logic: negative amounts must not post as valid credits (debit bypass).
    """
    em = f"dast-neg-{uuid.uuid4().hex[:8]}@clearledger.local"
    _register_or_login(em, "Pass123456!")
    tok, _ = _login(em, "Pass123456!")
    r = _req(
        "POST",
        "/ledger/transactions",
        headers={"Authorization": f"Bearer {tok}"},
        json_body={"amount": -5000, "direction": "credit"},
    )
    if r.status_code in (400, 422):
        return True, "Negative amount rejected"
    _print_fail(
        "Negative amount",
        f"POST {BASE_URL}/ledger/transactions amount=-5000",
        r,
        f"expected 400/422, got {r.status_code}",
    )
    return False, "negative amount accepted"


def test_jwt_none_algorithm() -> tuple[bool, str]:
    """
    JWT 'none' algorithm downgrade: must always be rejected.
    Fintech impact: total auth bypass if accepted.
    """
    if not JWT_SECRET:
        return (
            False,
            "JWT_SECRET unset — cannot forge tokens; set to match auth-service signing key",
        )
    header = _b64url(json.dumps({"alg": "none", "typ": "JWT"}).encode())
    payload = _b64url(
        json.dumps({"sub": "attacker", "exp": int(time.time()) + 3600}).encode()
    )
    token = f"{header}.{payload}."
    r = _req(
        "GET",
        "/ledger/balance",
        headers={"Authorization": f"Bearer {token}"},
    )
    if r.status_code == 401:
        return True, "JWT none algorithm rejected"
    _print_fail(
        "JWT none",
        f"GET {BASE_URL}/ledger/balance with alg=none token",
        r,
        f"expected 401, got {r.status_code}",
    )
    return False, "JWT none accepted"


def test_jwt_expired_token() -> tuple[bool, str]:
    """
    Expired JWT must be rejected — limits replay window for stolen tokens.
    """
    if not JWT_SECRET:
        return (
            False,
            "JWT_SECRET unset — cannot sign expired token; set to match auth-service",
        )
    header = _b64url(json.dumps({"alg": "HS256", "typ": "JWT"}).encode())
    body = {
        "sub": str(uuid.uuid4()),
        "exp": 1,
        "iat": 1,
        "email": "expired@x.local",
    }
    payload = _b64url(json.dumps(body).encode())
    sig = _b64url(
        hmac.new(
            JWT_SECRET.encode(),
            f"{header}.{payload}".encode(),
            hashlib.sha256,
        ).digest()
    )
    token = f"{header}.{payload}.{sig}"
    r = _req(
        "GET",
        "/ledger/balance",
        headers={"Authorization": f"Bearer {token}"},
    )
    if r.status_code == 401:
        return True, "JWT expiry enforced"
    _print_fail(
        "JWT expired",
        f"GET {BASE_URL}/ledger/balance with exp=1",
        r,
        f"expected 401, got {r.status_code}",
    )
    return False, "expired JWT accepted"


def _fetch_alerts() -> list[dict[str, Any]]:
    r = _req("GET", "/notifications/alerts")
    if r.status_code != 200:
        raise RuntimeError(f"/notifications/alerts: {r.status_code} {r.text}")
    data = r.json()
    return list(data.get("alerts") or [])


def _wait_for_alert_tx(transaction_id: str, *, deadline_s: float = 12.0) -> bool:
    end = time.monotonic() + deadline_s
    while time.monotonic() < end:
        for a in _fetch_alerts():
            if a.get("transaction_id") == transaction_id:
                return True
        time.sleep(0.5)
    return False


def test_large_transaction_bypass() -> tuple[bool, str]:
    """
    Large-transaction monitoring: amounts below the ledger notification threshold
    must not raise LARGE_TRANSACTION alerts; amounts at/above threshold must.
    Fintech impact: AML / fraud monitoring must not be bypassed around policy limits.
    """
    em = f"dast-large-{uuid.uuid4().hex[:8]}@clearledger.local"
    _register_or_login(em, "Pass123456!")
    tok, uid = _login(em, "Pass123456!")
    r1 = _req(
        "POST",
        "/ledger/transactions",
        headers={"Authorization": f"Bearer {tok}"},
        json_body={"amount": 9999.99, "direction": "credit"},
    )
    if r1.status_code != 201:
        _print_fail(
            "Large transaction threshold",
            f"POST {BASE_URL}/ledger/transactions 9999.99",
            r1,
            "expected 201",
        )
        return False, "under-threshold create failed"
    tx_small = r1.json()["id"]
    time.sleep(2.0)
    for a in _fetch_alerts():
        if a.get("transaction_id") == tx_small:
            ra = _req("GET", "/notifications/alerts")
            _print_fail(
                "Large transaction threshold",
                f"GET {BASE_URL}/notifications/alerts (unexpected alert for {tx_small})",
                ra,
                "sub-threshold transaction must not trigger LARGE_TRANSACTION",
            )
            return False, "false positive alert under threshold"

    r2 = _req(
        "POST",
        "/ledger/transactions",
        headers={"Authorization": f"Bearer {tok}"},
        json_body={"amount": 10000.01, "direction": "credit"},
    )
    if r2.status_code != 201:
        _print_fail(
            "Large transaction threshold",
            f"POST {BASE_URL}/ledger/transactions 10000.01",
            r2,
            "expected 201",
        )
        return False, "over-threshold create failed"
    tx_large = r2.json()["id"]
    if not _wait_for_alert_tx(tx_large):
        _print_fail(
            "Large transaction threshold",
            f"wait for alert transaction_id={tx_large} user_id={uid}",
            _req("GET", "/notifications/alerts"),
            "no LARGE_TRANSACTION alert observed via /notifications/alerts",
        )
        return False, "alert did not fire for amount >= threshold"
    return True, "Large transaction alert threshold correct"


def test_mass_assignment() -> tuple[bool, str]:
    """
    Mass assignment: client-supplied user_id must not override server-side identity.
    """
    em = f"dast-mass-{uuid.uuid4().hex[:8]}@clearledger.local"
    _register_or_login(em, "Pass123456!")
    tok, uid = _login(em, "Pass123456!")
    fake_other = str(uuid.uuid4())
    r = _req(
        "POST",
        "/ledger/transactions",
        headers={"Authorization": f"Bearer {tok}"},
        json_body={
            "amount": 100.0,
            "direction": "credit",
            "user_id": fake_other,
        },
    )
    if r.status_code != 201:
        _print_fail("Mass assignment", "POST /ledger/transactions", r, "expected 201")
        return False, "create failed"
    got = r.json().get("user_id")
    if got == uid:
        return True, "Mass assignment blocked"
    _print_fail(
        "Mass assignment",
        "POST /ledger/transactions with injected user_id",
        r,
        f"response user_id={got!r} expected authenticated {uid!r}",
    )
    return False, "user_id override accepted"


def main() -> int:
    tests = [
        test_bola_transaction_access,
        test_negative_amount_transaction,
        test_jwt_none_algorithm,
        test_jwt_expired_token,
        test_large_transaction_bypass,
        test_mass_assignment,
    ]
    rows: list[tuple[str, bool, str]] = []
    failed = False
    for fn in tests:
        try:
            ok, label = fn()
        except Exception as ex:  # noqa: BLE001 — surface any infra failure
            ok = False
            label = str(ex)
            print(f"\n[FAIL] {fn.__name__}: {ex}")
        status = "PASS" if ok else "FAIL"
        print(f"[{status}] {label}")
        rows.append((label, ok, fn.__name__))
        if not ok:
            failed = True
    print("\nSummary")
    print("-" * 72)
    for label, ok, name in rows:
        status = "PASS" if ok else "FAIL"
        print(f"[{status}] {label} ({name})")
    print("-" * 72)
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
