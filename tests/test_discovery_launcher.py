"""Reproduce Discovery's code call with scriptName and outputMounts only.

Run with: python tests/test_discovery_launcher.py
Requires the existing acpype-discovery:2026-10-07 image and Docker Desktop.
"""

import json
from pathlib import Path
import re
import shlex
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]


class DiscoveryLauncherTest(unittest.TestCase):
    def run_script(self, script, expected_exit):
        definition = json.loads((ROOT / 'acpype-tool.json').read_text())
        environment = next(item for item in definition['code_environments'] if item['language'] == 'python')
        with tempfile.TemporaryDirectory(prefix='discovery-regression-', dir=ROOT / 'test-output') as directory:
            scratch = Path(directory)
            scripts = scratch / 'scripts'
            output = scratch / 'output'
            scripts.mkdir()
            output.mkdir()
            (scripts / 'script with spaces.py').write_text(script, newline='\n')
            # Only scriptName is substituted. outputMounts is an output-capture
            # configuration, not an output_directory template argument.
            variables = {'scriptName': 'scripts/script with spaces.py'}
            command = re.sub(r'{{\s*(\w+)\s*}}', lambda match: variables.get(match[1], ''), environment['command'])
            result = subprocess.run([
                'docker', 'run', '--rm', '--init', '--network', 'none',
                '--mount', f'type=bind,source={scripts},target=/scripts,readonly',
                '--mount', f'type=bind,source={output},target=/work',
                'acpype-discovery:2026-10-07', *shlex.split(command),
            ], capture_output=True, text=True)
            self.assertEqual(result.returncode, expected_exit, result.stdout + result.stderr)
            log = output / 'logs.out'
            self.assertTrue(log.is_file(), 'Discovery must capture logs.out inside /work')
            if expected_exit == 0:
                topology = output / 'ETHANE.acpype'
                for name in ('ETHANE_AC.prmtop', 'ETHANE_AC.inpcrd', 'ETHANE_GMX.top', 'ETHANE_GMX.itp', 'ETHANE_GMX.gro'):
                    self.assertGreater((topology / name).stat().st_size, 0, name)
                self.assertIn('Ethane topology verified', log.read_text())
            else:
                self.assertIn('Expected script failure', log.read_text())

    def test_ethane_without_output_directory_parameter(self):
        self.run_script('''import os
from pathlib import Path
import subprocess
assert os.getcwd() == "/work"
subprocess.run(["acpype", "-i", "CC", "-b", "ETHANE", "-n", "0", "-c", "gas", "-a", "amber"], check=True)
assert Path("ETHANE.acpype/ETHANE_GMX.top").stat().st_size > 0
print("Ethane topology verified")
''', 0)

    def test_failure_exit_status_is_preserved(self):
        self.run_script('import sys\nprint("Expected script failure", file=sys.stderr)\nraise SystemExit(23)\n', 23)


if __name__ == '__main__':
    (ROOT / 'test-output').mkdir(exist_ok=True)
    unittest.main(verbosity=2)
