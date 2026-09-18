import importlib.util
import json
from pathlib import Path
import tempfile
import subprocess
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location(
    "diagnostic", Path(__file__).resolve().parents[1] / "diagnose_browser_auth.py"
)
diagnostic = importlib.util.module_from_spec(spec)
spec.loader.exec_module(diagnostic)


class BrowserAuthDiagnosticTests(unittest.TestCase):
    def test_wrong_url_can_be_corrected_without_restarting_attempt(self):
        with patch.object(diagnostic.getpass, "getpass", side_effect=[
            "https://example.test/connect/authorize?state=s",
            diagnostic.REDIRECT_URI + "?state=wrong&code=a",
            diagnostic.REDIRECT_URI + "?state=s&code=correct",
        ]), patch("builtins.print"):
            self.assertEqual(diagnostic.prompt_callback_code("s"), "correct")

    def test_missing_macos_roots_use_system_bundle_and_identify_requests(self):
        with patch.object(diagnostic.ssl, "create_default_context") as create, \
                patch.object(diagnostic.sys, "platform", "darwin"), \
                patch.dict(diagnostic.os.environ, {}, clear=True), \
                patch.object(diagnostic.Path, "is_file", return_value=True), \
                patch.object(diagnostic.urllib.request, "build_opener") as build:
            create.return_value.get_ca_certs.return_value = []
            diagnostic.https_opener()
            create.return_value.load_verify_locations.assert_called_once_with(cafile="/etc/ssl/cert.pem")
            self.assertIn(("User-Agent", "Strnadi-OAuth-Diagnostic/1.0"), build.return_value.addheaders)

    def test_explicit_ca_configuration_is_preserved(self):
        with patch.object(diagnostic.ssl, "create_default_context") as create, \
                patch.object(diagnostic.sys, "platform", "darwin"), \
                patch.dict(diagnostic.os.environ, {"SSL_CERT_FILE": "/custom/roots.pem"}, clear=True), \
                patch.object(diagnostic.urllib.request, "build_opener"):
            create.return_value.get_ca_certs.return_value = []
            diagnostic.https_opener()
            create.return_value.load_verify_locations.assert_not_called()

    def test_real_signature_and_tampered_or_truncated_tokens(self):
        with tempfile.TemporaryDirectory() as folder:
            private = str(Path(folder) / "private.pem")
            subprocess.run(["openssl", "genrsa", "-out", private, "2048"],
                           check=True, capture_output=True)
            modulus = subprocess.run(
                ["openssl", "rsa", "-in", private, "-noout", "-modulus"],
                check=True, capture_output=True,
            ).stdout.decode().strip().split("=", 1)[1]
            jwks = {"keys": [{"kid": "test", "alg": "RS256", "kty": "RSA",
                              "n": diagnostic.b64url(bytes.fromhex(modulus)), "e": "AQAB"}]}
            header = diagnostic.b64url(b'{"alg":"RS256","kid":"test"}')
            payload = diagnostic.b64url(b'{"sub":"test"}')
            message = header + "." + payload
            signature = subprocess.run(
                ["openssl", "dgst", "-sha256", "-sign", private],
                input=message.encode(), check=True, capture_output=True,
            ).stdout
            token = message + "." + diagnostic.b64url(signature)
            self.assertEqual(diagnostic.verify_signature(token, jwks)["status"], "valid")
            tampered = header + "." + diagnostic.b64url(b'{"sub":"other"}') + "." + token.split(".")[2]
            self.assertEqual(diagnostic.verify_signature(tampered, jwks)["status"], "invalid")
            truncated = message + "." + diagnostic.b64url(signature[:-8])
            result = diagnostic.verify_signature(truncated, jwks)
            self.assertEqual(result["status"], "invalid")
            self.assertEqual(result["expected_signature_bytes"], 256)
            self.assertEqual(result["actual_signature_bytes"], 248)
            self.assertEqual(diagnostic.verify_signature(token, {"keys": []})["status"], "key_not_found")

    def test_unsigned_and_opaque_tokens_do_not_pass(self):
        unsigned = diagnostic.b64url(b'{"alg":"none"}') + ".payload."
        self.assertEqual(diagnostic.verify_signature(unsigned, {"keys": []})["status"], "unsupported")
        self.assertEqual(diagnostic.verify_signature("opaque", {"keys": []})["status"], "not_verifiable")

    def test_callback_requires_exact_redirect_state_and_single_code(self):
        base = diagnostic.REDIRECT_URI
        self.assertEqual(diagnostic.callback_code(base + "?state=s&code=a%2Bb", "s"), "a+b")
        for url in [base + "?state=wrong&code=a", base + "?state=s&code=a&code=b",
                    base + "?state=s&code=a#fragment", base + "/?state=s&code=a",
                    base + "?state=s&error=denied", base + "?state=s&state=s&code=a"]:
            with self.subTest(url=url), self.assertRaises(ValueError):
                diagnostic.callback_code(url, "s")

    def test_signature_is_not_truncated(self):
        signature = bytes(range(256))
        token = "header.payload." + diagnostic.b64url(signature)
        summary = diagnostic.token_summary(token)
        self.assertEqual(summary["signature_bytes"], 256)
        self.assertEqual(summary["segment_characters"][-1], 342)
        self.assertEqual(summary["characters"], len(token))

    def test_exchange_preserves_exact_response_and_token(self):
        token = "header.payload." + "x" * 342
        raw = json.dumps({"access_token": token, "refresh_token": "fake"}).encode()
        class Response:
            status = 200
            def __enter__(self): return self
            def __exit__(self, *args): pass
            def read(self): return raw
        with tempfile.TemporaryDirectory() as folder:
            directory = Path(folder)
            with patch.object(diagnostic.urllib.request, "build_opener") as factory:
                factory.return_value.open.return_value = Response()
                with patch("builtins.print"):
                    actual, _ = diagnostic.exchange(
                        "https://example.test/connect/token", {"code": "a+b"}, directory, "project"
                    )
                request = factory.return_value.open.call_args.args[0]
                self.assertEqual(request.data, b"code=a%2Bb")
            self.assertEqual(actual, token)
            self.assertEqual((directory / "project-token.txt").read_bytes(), token.encode())
            self.assertEqual((directory / "project-response.json").read_bytes(), raw)
            self.assertEqual((directory / "project-token.txt").stat().st_mode & 0o777, 0o600)


if __name__ == "__main__":
    unittest.main()
