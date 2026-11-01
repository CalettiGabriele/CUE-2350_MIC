#!/usr/bin/env python3
"""Exercise the real bundling CLI and codesign without the user's app or keychain."""
import hashlib
import os
from pathlib import Path
import signal
import subprocess
import tempfile
import unittest
import uuid


BUNDLE = Path(__file__).resolve().with_name("bundle.sh")


class BundlePublicationTests(unittest.TestCase):
    def test_last_verified_bundle_survives_signing_failure_and_interruption(self):
        with tempfile.TemporaryDirectory(prefix="cue-bundle-test-") as directory:
            output = Path(directory).resolve()
            app = output / "CUE-2350 MIC.app"
            environment = {**os.environ, "BUNDLE_OUTPUT_DIR": str(output), "SIGN_IDENTITY": "-"}

            def run(*arguments, identity="-", check=True):
                result = subprocess.run(
                    [str(BUNDLE), *arguments],
                    env={**environment, "SIGN_IDENTITY": identity},
                    text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=600,
                )
                if check and result.returncode:
                    self.fail(result.stdout)
                return result

            def prepare():
                result = run("--prepare")
                for line in result.stdout.splitlines():
                    if line.startswith("Prepared unsigned app: "):
                        return Path(line.removeprefix("Prepared unsigned app: "))
                self.fail(result.stdout)

            def snapshot():
                return (
                    app.stat().st_ino,
                    {str(path.relative_to(app)): hashlib.sha256(path.read_bytes()).hexdigest()
                     for path in app.rglob("*") if path.is_file()},
                )

            first = prepare()
            (first / "Contents/Resources/publication-check.txt").write_text("previous verified app")
            run("--finalize", str(first))
            baseline = snapshot()

            rejected = prepare()
            failure = run("--finalize", str(rejected), identity=f"Missing-{uuid.uuid4()}", check=False)
            self.assertNotEqual(failure.returncode, 0, failure.stdout)
            self.assertEqual(snapshot(), baseline, "failed signing changed the published bundle")
            self.assertFalse(rejected.parent.exists(), "failed signing left a staging directory")

            interrupted = prepare()
            process = subprocess.Popen(
                [str(BUNDLE), "--finalize", str(interrupted)], env=environment,
                text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, start_new_session=True,
            )
            try:
                for line in process.stdout:
                    if line.startswith("Signing staged app with identity:"):
                        os.killpg(process.pid, signal.SIGTERM)
                        break
                remainder = process.communicate(timeout=30)[0]
                self.assertNotEqual(process.returncode, 0, remainder)
            finally:
                if process.poll() is None:
                    os.killpg(process.pid, signal.SIGKILL)
                    process.communicate()
            self.assertEqual(snapshot(), baseline, "interruption changed the published bundle")
            self.assertFalse(interrupted.parent.exists(), "interruption left a staging directory")

            replacement = prepare()
            (replacement / "Contents/Resources/publication-check.txt").write_text("new verified app")
            run("--finalize", str(replacement))
            self.assertEqual((app / "Contents/Resources/publication-check.txt").read_text(), "new verified app")
            self.assertNotEqual(app.stat().st_ino, baseline[0])
            self.assertFalse(replacement.parent.exists(), "successful publication left the old bundle")
            self.assertEqual(list(app.rglob("*.cstemp")), [])
            subprocess.run(["codesign", "--verify", "--deep", "--strict", str(app)], check=True)


if __name__ == "__main__":
    unittest.main()
