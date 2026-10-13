import importlib.util
import json
from pathlib import Path
import stat
import tempfile
import unittest
from unittest import mock
import zipfile

SPEC = importlib.util.spec_from_file_location('release', Path(__file__).parents[1] / 'release.py')
r = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(r)


class ReleasePolicyTests(unittest.TestCase):
    def test_regular_release_configuration_is_consistent(self):
        cfg = r.config()
        self.assertEqual(cfg['version'], '0.2.0')
        self.assertGreater(int(cfg['build']), 3)
        self.assertFalse(cfg['prerelease'])
        self.assertEqual(cfg['architecture'], 'arm64')

    def test_local_rehearsal_cannot_upload_even_with_unsigned_override(self):
        for signing in ['adhoc', 'developer-id', 'notarized']:
            with self.assertRaises(r.ReleaseError):
                r.publication_allowed({'signing': signing, 'local_only': True}, True)

    def test_unsigned_upload_is_an_explicit_choice_and_notarized_can_proceed(self):
        for signing in ['adhoc', 'developer-id']:
            with self.assertRaises(r.ReleaseError):
                r.publication_allowed({'signing': signing, 'local_only': False}, False)
            r.publication_allowed({'signing': signing, 'local_only': False}, True)
        r.publication_allowed({'signing': 'notarized', 'local_only': False}, False)

    def test_bundle_fingerprint_detects_resource_and_executable_mode_changes(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            binary = root / 'binary'
            binary.write_bytes(b'binary')
            binary.chmod(0o755)
            first = r.tree_digest(root)
            binary.chmod(0o644)
            self.assertNotEqual(first, r.tree_digest(root))
            binary.chmod(0o755)
            self.assertEqual(first, r.tree_digest(root))
            (root / 'icon').write_bytes(b'icon')
            self.assertNotEqual(first, r.tree_digest(root))

    def test_bundle_symlink_is_rejected(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            (root / 'escape').symlink_to('/etc')
            with self.assertRaises(r.ReleaseError): r.tree_digest(root)

    def test_zip_paths_and_symlinks_are_checked_before_extraction(self):
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / 'test.zip'
            for name in ['/tmp/escape', '../escape', r.APP + '/../escape', 'unexpected/file']:
                with zipfile.ZipFile(path, 'w') as zipped: zipped.writestr(name, 'bad')
                with self.assertRaises(r.ReleaseError): r.validate_zip(path)
            with zipfile.ZipFile(path, 'w') as zipped:
                info = zipfile.ZipInfo(r.APP + '/link')
                info.create_system = 3
                info.external_attr = (stat.S_IFLNK | 0o777) << 16
                zipped.writestr(info, '/etc')
            with self.assertRaises(r.ReleaseError): r.validate_zip(path)
            with zipfile.ZipFile(path, 'w') as zipped:
                zipped.writestr(r.APP + '/Contents/Info.plist', 'ok')
                zipped.writestr('__MACOSX/._' + r.APP, 'metadata')
            r.validate_zip(path)

    def test_unknown_signing_state_is_rejected_on_load(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            (root / 'manifest.json').write_text(json.dumps({'signing': 'trusted-me', 'local_only': False}))
            with self.assertRaises(r.ReleaseError): r.load(root)

    def test_github_is_not_called_when_local_artifact_verification_fails(self):
        args = type('Args', (), {'output': Path('/does-not-exist'), 'allow_unnotarized': True})()
        with mock.patch.object(r, 'run') as run:
            with self.assertRaises(FileNotFoundError): r.github(args)
            run.assert_not_called()

    def test_interrupted_submission_never_automatically_resubmits(self):
        args = type('Args', (), {'output': Path('/tmp/unused'), 'keychain_profile': 'test', 'submission_id': None})()
        manifest = {'local_only': False, 'signing': 'developer-id', 'notary_pending_submission': True}
        with mock.patch.object(r, 'verify', return_value=manifest), mock.patch.object(r, 'run') as run:
            with self.assertRaises(r.ReleaseError): r.notarize(args)
            run.assert_not_called()

    def test_rejected_notarization_never_staples_or_reports_acceptance(self):
        args = type('Args', (), {'output': Path('/tmp/unused'), 'keychain_profile': 'test', 'submission_id': None})()
        manifest = {'local_only': False, 'signing': 'developer-id', 'notary_id': 'known-id', 'assets': {'app.zip': 'hash'}}
        response = json.dumps({'name': 'app.zip', 'status': 'Invalid'})
        with mock.patch.object(r, 'verify', return_value=manifest), mock.patch.object(r, 'run', return_value=response) as run, mock.patch.object(r, 'write_json'):
            with self.assertRaises(r.ReleaseError): r.notarize(args)
            self.assertEqual(run.call_count, 1)
            self.assertEqual(run.call_args[0][0][1:3], ['notarytool', 'info'])

    def test_in_progress_submission_is_only_queried_not_uploaded_again(self):
        args = type('Args', (), {'output': Path('/tmp/unused'), 'keychain_profile': 'test', 'submission_id': None})()
        manifest = {'local_only': False, 'signing': 'developer-id', 'notary_id': 'known-id', 'assets': {'app.zip': 'hash'}}
        response = json.dumps({'name': 'app.zip', 'status': 'In Progress'})
        with mock.patch.object(r, 'verify', return_value=manifest), mock.patch.object(r, 'run', return_value=response) as run, mock.patch.object(r, 'write_json'), mock.patch('builtins.print'):
            r.notarize(args)
            self.assertEqual(run.call_count, 1)
            self.assertEqual(manifest['signing'], 'developer-id')


if __name__ == '__main__': unittest.main()
