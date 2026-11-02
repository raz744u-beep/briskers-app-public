#!/usr/bin/env python3
"""Synthetic output fixtures; no keystore, credentials or APK are needed."""

import importlib.util
from pathlib import Path
import unittest

spec = importlib.util.spec_from_file_location(
    "apk_certificate", Path(__file__).resolve().parents[1] / "verify_apk_certificate.py"
)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
EXPECTED = "a1" * 32
OTHER = "b2" * 32


class CertificateOutputTests(unittest.TestCase):
    def test_legacy_label(self):
        self.assertEqual(module.verify(f"Signer #1 certificate SHA-256 digest: {EXPECTED}", EXPECTED), EXPECTED)

    def test_current_v2_label(self):
        self.assertEqual(module.verify(f"V2 Signer: certificate SHA-256 digest: {EXPECTED}", EXPECTED), EXPECTED)

    def test_same_certificate_across_schemes(self):
        output = "\n".join(f"V{scheme} Signer: certificate SHA-256 digest: {EXPECTED}" for scheme in [1, 2, 3])
        self.assertEqual(module.verify(output, EXPECTED), EXPECTED)

    def test_uppercase_digest(self):
        self.assertEqual(module.verify(f"V2 Signer: certificate SHA-256 digest: {EXPECTED.upper()}", EXPECTED), EXPECTED)

    def test_missing_digest_fails_closed(self):
        with self.assertRaises(ValueError):
            module.verify("Verified using v2 scheme: true", EXPECTED)

    def test_wrong_certificate_fails_closed(self):
        with self.assertRaises(ValueError):
            module.verify(f"V2 Signer: certificate SHA-256 digest: {OTHER}", EXPECTED)

    def test_extra_signer_is_not_ignored(self):
        output = f"Signer #1 certificate SHA-256 digest: {EXPECTED}\nSigner #2 certificate SHA-256 digest: {OTHER}"
        with self.assertRaises(ValueError):
            module.verify(output, EXPECTED)

    def test_other_scheme_is_not_ignored(self):
        output = f"V2 Signer: certificate SHA-256 digest: {EXPECTED}\nV3.1 Signer: certificate SHA-256 digest: {OTHER}"
        with self.assertRaises(ValueError):
            module.verify(output, EXPECTED)

    def test_malformed_extra_digest_fails_closed(self):
        output = f"V2 Signer: certificate SHA-256 digest: {EXPECTED}\nOther certificate SHA-256 digest: invalid"
        with self.assertRaises(ValueError):
            module.verify(output, EXPECTED)

    def test_invalid_pin_fails_closed(self):
        with self.assertRaises(ValueError):
            module.verify(f"V2 Signer: certificate SHA-256 digest: {EXPECTED}", "")


if __name__ == "__main__":
    unittest.main()
