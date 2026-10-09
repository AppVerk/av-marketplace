"""Subprocess regressions for names-file validation and URL redaction.

Run: uv run python -m unittest discover -s plugins/qa/tests -p test_redact.py
"""
from __future__ import annotations

import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

REDACTOR = Path(__file__).resolve().parents[1] / "skills/be-testing/scripts/qa-redact.pl"


class RedactTests(unittest.TestCase):
    def setUp(self) -> None:
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.names_file = Path(temporary.name) / "redact-names"

    def redact(
        self,
        body: str,
        *,
        names: tuple[str, ...] = (),
        values: dict[str, str] | None = None,
    ) -> subprocess.CompletedProcess[str]:
        self.names_file.write_text(
            "".join(f"{name}\n" for name in names), encoding="utf-8",
        )
        environment = {
            name: value
            for name, value in os.environ.items()
            if not name.startswith(("QA_", "PG", "MYSQL_", "REDIS", "STORE_")) and name != "SQLITE_DB"
        }
        environment.update(values or {})

        return subprocess.run(
            ["perl", str(REDACTOR), str(self.names_file)],
            input=body,
            env=environment,
            capture_output=True,
            text=True,
            check=False,
            timeout=10,
        )

    def test_db_port_names_are_accepted_without_masking_body_values(self) -> None:
        body = {
            "postgresPort": "54322",
            "mysqlPort": "3307",
            "redisPort": "6379", "redisDb": "0",
            "message": "Postgres listens on 54322; MySQL listens on 3307; Redis listens on 6379.",
            "avatarUrl": "http://localhost:54322/storage/avatars/user.png",
        }
        result = self.redact(
            json.dumps(body),
            names=("PGPORT", "MYSQL_TCP_PORT", "REDIS_PORT", "REDIS_DB"),
            values={"PGPORT": "54322", "MYSQL_TCP_PORT": "3307", "REDIS_PORT": "6379", "REDIS_DB": "0"},
        )

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(json.loads(result.stdout), body)

    def test_qa_values_with_client_port_suffixes_are_masked(self) -> None:
        for suffix in ("PGPORT", "MYSQL_TCP_PORT", "REDIS_PORT", "REDIS_DB"):
            with self.subTest(suffix=suffix):
                values = {
                    suffix: "5400",
                    f"STORE_MAIN_{suffix}": "5401",
                    f"QA_{suffix}": "private-direct",
                    f"QA_LEGACY_{suffix}": "private-legacy",
                }
                result = self.redact(
                    json.dumps({
                        "native": "5400",
                        "store": "5401",
                        "message": ["private-direct", "private-legacy"],
                    }),
                    names=tuple(values),
                    values=values,
                )

                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(json.loads(result.stdout), {
                    "native": "5400",
                    "store": "5401",
                    "message": ["***", "***"],
                })

    def test_captured_credential_names_are_masked_under_any_key(self) -> None:
        result = self.redact(
            '{"message":"welcome private-token"}',
            names=("QA_CAPTURED_OWNER_TOKEN",),
            values={"QA_CAPTURED_OWNER_TOKEN": "private-token"},
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(json.loads(result.stdout), {"message": "welcome ***"})

    def test_store_names_and_redis_credentials_are_masked(self) -> None:
        values = {"REDIS_HOST": "cache.internal", "REDISCLI_AUTH": "cache-secret",
                  "STORE_MAIN_PGPASSWORD": "sql-secret", "STORE_CACHE_REDIS_PORT": "6379",
                  "STORE_CACHE_REDIS_DB": "0"}
        result = self.redact(json.dumps(values), names=tuple(values), values=values)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(json.loads(result.stdout), {**values, "REDIS_HOST": "***", "REDISCLI_AUTH": "***", "STORE_MAIN_PGPASSWORD": "***"})

    def test_captured_cookie_masks_its_value_when_echoed_under_any_key(self) -> None:
        for name, cookie in (("QA_CAPTURED_OWNER_COOKIE", "session=x'y"), ("QA_CAPTURED_OWNER_COOKIE_2", "session=x'y; Path=/")):
            with self.subTest(name=name):
                result = self.redact(
                    json.dumps({"note": "x'y", "message": cookie, "public": "welcome"}),
                    names=(name,),
                    values={name: cookie},
                )
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(json.loads(result.stdout), {"note": "***", "message": "***", "public": "welcome"})

    def test_short_captured_cookie_preserves_status_and_numbers(self) -> None:
        for value in ("1", "12"):
            with self.subTest(value=value):
                cookie = f"consent={value}"
                body = {"id": 10, "count": 1, "code": 123, "note": value, "cookie": cookie}
                result = self.redact(
                    f"HTTP/1.1 201 Created\r\nSet-Cookie: {cookie}\r\n\r\n" + json.dumps(body),
                    names=("QA_CAPTURED_OWNER_COOKIE",),
                    values={"QA_CAPTURED_OWNER_COOKIE": cookie},
                )
                self.assertEqual(result.returncode, 0, result.stderr)
                headers, sanitized = result.stdout.split("\n\n", 1)
                self.assertEqual(headers.splitlines(), ["HTTP/1.1 201 Created", "Set-Cookie: ***"])
                self.assertEqual(json.loads(sanitized), {**body, "cookie": "***"})

    def test_unknown_or_malformed_names_abort_without_emitting_the_body(self) -> None:
        invalid_names = (
            "UNDECLARED_TOKEN",
            "AV_TOKEN",
            "PGPORT_EXTRA",
            "MYSQL_TCP_PORT_EXTRA",
            "pgport",
            "QA_",
            "QA_TOKEN-INVALID",
            " QA_TOKEN",
            "QA_TOKEN ",
            "PGPORT=54322",
            "",
        )

        for name in invalid_names:
            with self.subTest(name=name):
                result = self.redact(
                    '{"message":"response must not escape"}',
                    names=("PGPORT", "MYSQL_TCP_PORT", "QA_TOKEN", name),
                    values={"PGPORT": "54322", "MYSQL_TCP_PORT": "3307", "QA_TOKEN": "secret"},
                )

                self.assertNotEqual(result.returncode, 0)
                self.assertEqual(result.stdout, "")
                self.assertIn("invalid names file", result.stderr)

    def test_avatar_url_keeps_its_path_but_masks_query_and_fragment(self) -> None:
        path = "/storage/v1/object/sign/avatars/user-42/avatar.png"
        result = self.redact(json.dumps({
            "avatarUrl": f"https://storage.test:54321{path}?token=signed-secret&download=1#private-fragment",
        }))

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(
            json.loads(result.stdout),
            {"avatarUrl": f"https://storage.test:54321{path}?***#***"},
        )

    def test_one_time_and_credential_keys_stay_fully_masked(self) -> None:
        sensitive_keys = ("resetUrl", "confirmUrl", "accessToken", "apiKey", "sessionUrl")

        for key in sensitive_keys:
            with self.subTest(key=key):
                result = self.redact(json.dumps({
                    key: "https://accounts.test/private/one-time-secret?token=secret",
                    "status": "ready",
                }))

                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(json.loads(result.stdout), {key: "***", "status": "ready"})

    def test_signed_url_masks_userinfo_without_losing_the_public_path(self) -> None:
        result = self.redact(json.dumps({
            "signedURL": "https://uploader:private-password@storage.test:8443/public/avatar.png?token=signature",
        }))

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(json.loads(result.stdout), {
            "signedURL": "https://***@storage.test:8443/public/avatar.png?***",
        })
        self.assertNotIn("private-password", result.stdout)

    def test_declared_values_are_masked_inside_an_otherwise_visible_url_path(self) -> None:
        result = self.redact(
            json.dumps({
                "avatarUrl": "https://storage.test/storage/v1/object/sign/avatars/private-avatar-id/photo.png?token=signature",
                "label": "Avatar private-avatar-id",
            }),
            names=("QA_AVATAR_ID",),
            values={"QA_AVATAR_ID": "private-avatar-id"},
        )

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(json.loads(result.stdout), {
            "avatarUrl": "https://storage.test/storage/v1/object/sign/avatars/***/photo.png?***",
            "label": "Avatar ***",
        })
        self.assertNotIn("private-avatar-id", result.stdout)

    def test_non_json_bodies_are_withheld_with_or_without_http_headers(self) -> None:
        bodies = (
            "private response body",
            '<html><body>password="private-password"</body></html>',
            '{"avatarUrl":"https://storage.test/private-token",',
        )
        headers = "HTTP/1.1 200 OK\r\nContent-Type: text/plain\r\n\r\n"

        for body in bodies:
            for prefix in ("", headers):
                with self.subTest(body=body, http=bool(prefix)):
                    result = self.redact(prefix + body)

                    self.assertEqual(result.returncode, 0, result.stderr)
                    self.assertIn("[body withheld by qa-redact:", result.stdout)
                    self.assertNotIn(body, result.stdout)
                    self.assertNotIn("private-password", result.stdout)
                    self.assertNotIn("private-token", result.stdout)


if __name__ == "__main__":
    unittest.main()
