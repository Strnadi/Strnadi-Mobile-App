#!/usr/bin/env python3
"""Interactive, dependency-free reproduction of the mobile OAuth flow."""

import argparse
import base64
import getpass
import hashlib
import json
import os
from pathlib import Path
import secrets
import ssl
import subprocess
import sys
import tempfile
import urllib.error
import urllib.parse
import urllib.request
import uuid
import webbrowser

CLIENT_ID = "strnadi-app"
REDIRECT_URI = "com.delta.strnadi://auth/callback"
ROOT = Path(__file__).resolve().parents[1]


def b64url(value):
    return base64.urlsafe_b64encode(value).rstrip(b"=").decode("ascii")


def callback_code(callback, state):
    uri = urllib.parse.urlsplit(callback)
    params = urllib.parse.parse_qs(uri.query, keep_blank_values=True)
    if (callback.split("?", 1)[0] != REDIRECT_URI or uri.fragment
            or params.get("state") != [state]):
        raise ValueError("Callback URL or state does not match this attempt.")
    if "error" in params:
        raise ValueError("Browser authorization was denied or failed.")
    codes = params.get("code", [])
    if len(codes) != 1 or not codes[0].strip():
        raise ValueError("Callback must contain exactly one authorization code.")
    return codes[0]


def prompt_callback_code(state):
    while True:
        callback = getpass.getpass("Full callback URL (hidden): ").strip()
        if callback.startswith(("https://", "http://")):
            print("That is a website URL, not the completed login callback.")
            print("Complete login, then copy the final redirect's Location header:")
            print("com.delta.strnadi://auth/callback?code=...&state=...")
            continue
        try:
            return callback_code(callback, state)
        except ValueError:
            print("Callback rejected: expected the exact callback URL, one code, and this attempt's state.")
            print("Copy the complete Location header from this login attempt and try again.")
            print("If login was denied or this attempt expired, press Ctrl-C and restart.")


def token_summary(token):
    encoded = token.encode("utf-8")
    parts = token.split(".")
    summary = {
        "characters": len(token),
        "bytes": len(encoded),
        "sha256": hashlib.sha256(encoded).hexdigest(),
        "segments": len(parts),
        "segment_characters": [len(part) for part in parts],
    }
    if len(parts) == 3:
        try:
            signature = base64.b64decode(
                parts[2] + "=" * (-len(parts[2]) % 4), altchars=b"-_", validate=True
            )
            summary["signature_bytes"] = len(signature)
        except (ValueError, base64.binascii.Error):
            summary["signature_encoding"] = "invalid base64url"
    # Segment sizes alone do not prove completeness or cryptographic validity.
    return summary


def save_private(path, data):
    with path.open("xb") as output:
        os.chmod(path, 0o600)
        output.write(data)


def decode_url(value):
    return base64.b64decode(value + "=" * (-len(value) % 4), altchars=b"-_", validate=True)


def der(tag, value):
    size = len(value)
    length = bytes([size]) if size < 128 else (
        bytes([0x80 | ((size.bit_length() + 7) // 8)])
        + size.to_bytes((size.bit_length() + 7) // 8, "big")
    )
    return bytes([tag]) + length + value


def rsa_public_pem(key):
    def integer(value):
        raw = decode_url(value).lstrip(b"\0") or b"\0"
        return der(2, b"\0" + raw if raw[0] & 0x80 else raw)
    public = der(0x30, integer(key["n"]) + integer(key["e"]))
    # rsaEncryption AlgorithmIdentifier plus BIT STRING containing RSAPublicKey.
    spki = der(0x30, bytes.fromhex("300d06092a864886f70d0101010500") + der(3, b"\0" + public))
    encoded = base64.b64encode(spki)
    return (b"-----BEGIN PUBLIC KEY-----\n"
            + b"\n".join(encoded[i:i + 64] for i in range(0, len(encoded), 64))
            + b"\n-----END PUBLIC KEY-----\n")


def verify_signature(token, jwks):
    parts = token.split(".")
    if len(parts) != 3:
        return {"status": "not_verifiable", "reason": "Opaque or encrypted token, not a signed JWT"}
    try:
        header = json.loads(decode_url(parts[0]))
        alg, kid = header.get("alg"), header.get("kid")
        report = {"algorithm": alg, "key_id": kid}
        if alg != "RS256":
            return {**report, "status": "unsupported", "reason": "Only RS256 is supported"}
        keys = [key for key in jwks["keys"]
                if key.get("kid") == kid and key.get("kty") == "RSA"
                and key.get("use", "sig") == "sig" and key.get("alg", "RS256") == alg
                and "verify" in key.get("key_ops", ["verify"])]
        if not isinstance(kid, str) or len(keys) != 1:
            return {**report, "status": "key_not_found", "reason": "Expected one matching signing key"}
        key = keys[0]
        signature = decode_url(parts[2])
        expected_size = (int.from_bytes(decode_url(key["n"]), "big").bit_length() + 7) // 8
        report.update(expected_signature_bytes=expected_size, actual_signature_bytes=len(signature))
        if len(signature) != expected_size:
            return {**report, "status": "invalid", "reason": "Signature length differs from RSA key size"}
        with tempfile.TemporaryDirectory(prefix="strnadi-signature-") as folder:
            directory = Path(folder)
            save_private(directory / "key.pem", rsa_public_pem(key))
            save_private(directory / "signature.bin", signature)
            checked = subprocess.run(
                ["openssl", "dgst", "-sha256", "-verify", str(directory / "key.pem"),
                 "-signature", str(directory / "signature.bin")],
                input=(parts[0] + "." + parts[1]).encode("ascii"),
                capture_output=True, timeout=15,
            )
        return {**report, "status": "valid" if checked.returncode == 0 else "invalid"}
    except (ValueError, KeyError, TypeError, AttributeError, base64.binascii.Error):
        return {"status": "invalid", "reason": "Malformed JWT or signing key"}
    except (OSError, subprocess.TimeoutExpired):
        return {"status": "verification_error", "reason": "Could not run OpenSSL verification"}


def load_jwks(url, directory):
    uri = urllib.parse.urlsplit(url)
    if uri.scheme != "https" or not uri.hostname or uri.username or uri.password or uri.fragment:
        raise ValueError("JWKS URL must use HTTPS without credentials or fragment.")
    with https_opener().open(url, timeout=30) as response:
        raw = response.read()
    save_private(directory / "jwks.json", raw)
    jwks = json.loads(raw)
    if not isinstance(jwks, dict) or not isinstance(jwks.get("keys"), list):
        raise ValueError("Invalid JWKS response.")
    return jwks


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None


def https_opener():
    context = ssl.create_default_context()
    # Python.org macOS installations may have no installed CA bundle.
    # Respect explicit trust configuration; never disable TLS verification.
    if (sys.platform == "darwin" and not context.get_ca_certs()
            and "SSL_CERT_FILE" not in os.environ and "SSL_CERT_DIR" not in os.environ
            and Path("/etc/ssl/cert.pem").is_file()):
        context.load_verify_locations(cafile="/etc/ssl/cert.pem")
    opener = urllib.request.build_opener(
        NoRedirect(), urllib.request.HTTPSHandler(context=context)
    )
    opener.addheaders = [("User-Agent", "Strnadi-OAuth-Diagnostic/1.0"),
                         ("Accept", "application/json")]
    return opener


def exchange(endpoint, fields, directory, label, jwks=None):
    request = urllib.request.Request(
        endpoint,
        data=urllib.parse.urlencode(fields).encode("ascii"),
        headers={"Content-Type": "application/x-www-form-urlencoded",
                 "Accept": "application/json"},
    )
    opener = https_opener()
    try:
        with opener.open(request, timeout=30) as response:
            status, raw = response.status, response.read()
    except urllib.error.HTTPError as error:
        status, raw = error.code, error.read()
    save_private(directory / f"{label}-response.json", raw)
    if status != 200:
        raise ValueError(f"{label}: HTTP {status}; raw response saved locally.")
    payload = json.loads(raw)
    if not isinstance(payload, dict):
        raise ValueError(f"{label}: response is not a JSON object.")
    token = payload.get("access_token")
    if not isinstance(token, str) or not token:
        raise ValueError(f"{label}: response has no access token.")
    save_private(directory / f"{label}-token.txt", token.encode("utf-8"))
    summary = token_summary(token)
    if jwks is not None:
        summary["signature_verification"] = verify_signature(token, jwks)
    save_private(directory / f"{label}-summary.json", json.dumps(summary, indent=2).encode())
    print(f"\n{label}:\n{json.dumps(summary, indent=2)}")
    return token, summary


def configuration(environment):
    prefix = "" if environment == "prod" else environment
    define = "STRNADI_" + ("" if environment == "prod" else environment.upper() + "_")
    values = {
        "preprodadministrationurl": "https://preprod-administration.strnadi.cz/",
        "preprodprojectid": "01a08608-44b7-7aba-8d0c-542148b30bf2",
    }
    asset = ROOT / "assets/config.json"
    if asset.exists():
        values.update(json.loads(asset.read_text()))
    build = ROOT / "build.env.json"
    overrides = json.loads(build.read_text()) if build.exists() else {}
    return (
        overrides.get(define + "ADMINISTRATION_URL", values.get(prefix + "administrationurl")),
        overrides.get(define + "PROJECT_ID", values.get(prefix + "projectid")),
    )


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--environment", choices=["preprod", "dev", "prod"], default="preprod")
    parser.add_argument("--issuer", help="Override Administration HTTPS origin")
    parser.add_argument("--project-id", help="Override project UUID")
    parser.add_argument("--jwks-url", help="Defaults to the issuer's /.well-known/jwks")
    args = parser.parse_args()
    issuer, project = configuration(args.environment)
    issuer, project = args.issuer or issuer, args.project_id or project
    if not issuer or not project:
        parser.error("Configure this environment or supply --issuer and --project-id.")
    uri = urllib.parse.urlsplit(issuer)
    if (uri.scheme != "https" or not uri.hostname or uri.username or uri.password
            or uri.path not in ("", "/") or uri.query or uri.fragment):
        parser.error("Issuer must be an HTTPS origin without credentials, query or fragment.")
    project = str(uuid.UUID(project))
    issuer = issuer.rstrip("/")
    directory = Path(tempfile.mkdtemp(prefix="strnadi-auth-"))
    os.chmod(directory, 0o700)
    print(f"Environment: {args.environment}\nIssuer: {issuer}\nProject: {project}")
    print(f"Private results directory: {directory}")
    print("Results include live credentials (and a refresh token); delete the directory after use.")
    jwks_url = args.jwks_url or issuer + "/.well-known/jwks"
    print(f"Signing keys: {jwks_url}")
    jwks = load_jwks(jwks_url, directory)
    verifier, state = secrets.token_urlsafe(32), secrets.token_urlsafe(32)
    authorize = issuer + "/connect/authorize?" + urllib.parse.urlencode({
        "client_id": CLIENT_ID, "redirect_uri": REDIRECT_URI,
        "response_type": "code", "code_challenge": b64url(hashlib.sha256(verifier.encode()).digest()),
        "code_challenge_method": "S256", "state": state,
        "scope": "openid offline_access",
    })
    print("\n1. Open browser Developer Tools > Network and enable Preserve log.")
    print("2. Open the following URL in that tab and complete login:")
    print(authorize)
    print("3. Cancel any prompt to open Strnadi. In Network, copy the final redirect's")
    print("   Location header (com.delta.strnadi://auth/callback?code=...&state=...).")
    print("   Paste the full URL, not just the code. Do not reload it or share it here.")
    if input("Open a browser tab automatically? [y/N] ").strip().lower() == "y":
        webbrowser.open(authorize)
    code = prompt_callback_code(state)
    endpoint = issuer + "/connect/token"
    admin, admin_summary = exchange(endpoint, {
        "grant_type": "authorization_code", "code": code,
        "redirect_uri": REDIRECT_URI, "client_id": CLIENT_ID, "code_verifier": verifier,
    }, directory, "administration", jwks)
    _, project_summary = exchange(endpoint, {
        "grant_type": "urn:ietf:params:oauth:grant-type:token-exchange",
        "subject_token": admin,
        "subject_token_type": "urn:ietf:params:oauth:token-type:access_token",
        "client_id": CLIENT_ID, "project_id": project,
    }, directory, "project", jwks)
    save_private(directory / "summary.json", json.dumps({
        "administration": admin_summary, "project": project_summary,
    }, indent=2).encode())
    print(f"\nDone. Full tokens (no added newline) and raw responses: {directory}")
    print("RS256 signature results are above. This does not validate issuer, audience, or expiry.")
    print("A fresh login can issue different tokens. Compare structure and lengths;")
    print("only hashes of the SAME issued token establish exact equality.")
    return 0 if project_summary["signature_verification"]["status"] == "valid" else 1


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except urllib.error.HTTPError as error:
        print(f"HTTPS endpoint returned HTTP {error.code}. Login diagnostics could not complete.")
        raise SystemExit(1)
    except urllib.error.URLError as error:
        if isinstance(error.reason, ssl.SSLCertVerificationError):
            print("HTTPS certificate verification failed. Python could not verify the server's certificate.")
            print("Configure SSL_CERT_FILE with a trusted CA bundle and retry.")
        else:
            print(f"Network request failed ({type(error.reason).__name__}). Check connectivity and retry.")
        raise SystemExit(1)
    except (ValueError, OSError) as error:
        # Network exceptions may contain URLs; do not echo arbitrary details.
        print(f"Diagnostic stopped ({type(error).__name__}). Check saved responses locally.")
        raise SystemExit(1)
    except (KeyboardInterrupt, EOFError):
        print("\nCancelled.")
        raise SystemExit(130)
