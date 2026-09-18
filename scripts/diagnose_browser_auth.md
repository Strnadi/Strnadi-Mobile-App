# Browser authentication diagnostic

From the repository root, run:

```sh
python3 scripts/diagnose_browser_auth.py
```

Defaults to preprod, reading public OAuth settings from `assets/config.json`
and overrides from `build.env.json`. Select another environment with
`--environment dev` or `--environment prod`, or supply `--issuer` and
`--project-id`. Match the settings used to build the app being investigated.
No Python packages need installing. Signature checks require `openssl` on PATH
(available on macOS).
If Python on macOS has no CA trust roots installed, the script uses
`/etc/ssl/cert.pem`. TLS verification remains enabled. Explicit `SSL_CERT_FILE`
or `SSL_CERT_DIR` settings take precedence over this fallback.

Follow the terminal instructions. For the most reliable callback capture, use
a desktop browser with Developer Tools open and Network **Preserve log** enabled
before navigating to the printed authorization URL. After signing in, cancel
the prompt to open Strnadi. Find the final redirect response and copy its full
`Location` header beginning `com.delta.strnadi://auth/callback`. Paste it into
the script's hidden prompt. If automatic opening navigated before you enabled
Network capture, restart the script for a fresh attempt. Codes are single-use.

The script matches the app's client ID, redirect URI, scopes, S256 PKCE,
authorization-code exchange, and project-token exchange. It does not modify
the app or its stored session. It refuses token-endpoint redirects.

Each run prints a private temporary output directory. It contains the exact
response bodies, extracted full tokens without added newlines, and a summary
of token byte/character lengths, SHA-256 hashes, segment lengths, and decoded
JWT signature size. The script fetches the selected issuer's `/.well-known/jwks`
(preprod defaults to `https://preprod-administration.strnadi.cz/.well-known/jwks`)
and verifies RS256 signatures with OpenSSL using the matching `kid`, RSA modulus,
and exponent. Override the key endpoint with `--jwks-url` if needed. The fetched
JWKS and per-token verification reports are saved alongside the responses.
Administration tokens can be opaque or encrypted rather
than three-segment JWTs. Files contain live credentials, including any returned
refresh token; keep them local and delete the printed directory after diagnosis.

Inspect the token files in an editor to bypass console line-length limits.
This isolates the browser/server exchange from Flutter. A suspicious token
in the raw response was already present before app processing. A complete token
here alone does not prove what happened in a separate app login: newly issued
tokens may differ. A `valid` signature means the exact signed header and payload
verify against the selected public key; it does not validate issuer, audience,
expiry, or backend authorization. A signature length mismatch is reported
separately from a cryptographic verification failure. Unsupported algorithms,
opaque/encrypted tokens, missing keys, and verifier errors never report `valid`.
The script exits nonzero unless the project token's signature verifies.
Exact hashes are comparable only for the same issued token.

Offline checks:

```sh
python3 -m unittest discover -s scripts/tests -p 'test_diagnose_browser_auth.py'
```
