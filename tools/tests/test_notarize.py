"""Test release rejection handling without submitting anything to Apple."""
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

SCRIPT = Path(__file__).resolve().parents[1] / "notarize.sh"
JOB_ID = "6be52608-d47e-4af7-99cd-01eb0b1d0493"

class NotarizationTests(unittest.TestCase):
    def run_submission(self, response, exit_code=0):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "response.json").write_text(response)
            stub = root / "xcrun"
            stub.write_text('''#!/bin/bash
if [[ "$2" == submit ]]; then
    cat "$FIXTURE_DIR/response.json"
    exit "$FIXTURE_EXIT"
fi
if [[ "$2" == log ]]; then
    printf '{"issues":[{"message":"Test rejection"}]}' > "$6"
    touch "$FIXTURE_DIR/log-requested"
    exit 0
fi
exit 99
''')
            stub.chmod(0o755)
            environment = dict(os.environ, PATH=f"{root}:/usr/bin:/bin", IP_NOTARY_PROFILE="test",
                               FIXTURE_DIR=str(root), FIXTURE_EXIT=str(exit_code))
            result = subprocess.run(
                ["/bin/bash", "-c", 'set -eu; source "$1"; ip_notarize_and_wait "$2" "$3"; touch "$4"',
                 "test", str(SCRIPT), "test.zip", str(root / "submission.json"), str(root / "staple-reached")],
                env=environment, capture_output=True, text=True)
            return result, (root / "staple-reached").exists(), (root / "log-requested").exists()

    def test_accepted_can_continue_to_stapling(self):
        result, continued, logged = self.run_submission(json.dumps({"status": "Accepted", "id": JOB_ID}))
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue(continued)
        self.assertFalse(logged)

    def test_invalid_with_zero_exit_stops_and_fetches_log(self):
        result, continued, logged = self.run_submission(json.dumps({"status": "Invalid", "id": JOB_ID}))
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse(continued)
        self.assertTrue(logged)
        self.assertIn("Test rejection", result.stderr)

    def test_pending_stops_instead_of_stapling(self):
        result, continued, _ = self.run_submission(json.dumps({"status": "In Progress", "id": JOB_ID}))
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse(continued)

    def test_command_failure_stops(self):
        result, continued, _ = self.run_submission("", exit_code=1)
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse(continued)

    def test_invalid_json_stops(self):
        result, continued, _ = self.run_submission("not JSON")
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse(continued)

    def test_missing_status_stops(self):
        result, continued, _ = self.run_submission(json.dumps({"id": JOB_ID}))
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse(continued)

if __name__ == "__main__":
    unittest.main()
