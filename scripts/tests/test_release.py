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
    def test_current_notes_cover_full_changelog_interval(self):
        _, plan = r.current_notes()
        self.assertEqual(plan['included_versions'][-1], r.config()['version'])
        self.assertGreater(len(plan['included_versions']), 0)

    def test_skipped_public_versions_must_all_have_change_sections(self):
        log = '## 0.17.6 · final\n## 0.17.5 · intermediate\n## 0.17.2 · fix\n## 0.17.1 · published\n'
        plan = {'previous_release': 'v0.17.1', 'included_versions': ['0.17.2', '0.17.5', '0.17.6']}
        notes = '# Tile Launcher 0.17.6\n업데이트 범위: **v0.17.1 → v0.17.6**\n' + ''.join(f'### {v}\n- change\n' for v in plan['included_versions'])
        r.validate_notes_range(plan, '0.17.6', notes, log)
        missing = dict(plan, included_versions=['0.17.2', '0.17.6'])
        with self.assertRaises(r.ReleaseError): r.validate_notes_range(missing, '0.17.6', notes, log)
        with self.assertRaises(r.ReleaseError): r.validate_notes_range(plan, '0.17.6', notes.replace('### 0.17.5\n- change\n', ''), log)
        with self.assertRaises(r.ReleaseError): r.validate_notes_range(plan, '0.17.6', notes.replace('### 0.17.5\n- change', '### 0.17.5\n'), log)
        with self.assertRaises(r.ReleaseError): r.validate_notes_range(plan, '0.17.6', notes.replace('### 0.17.5\n', '### 0.17.50\n'), log)

    def test_previous_public_release_excludes_drafts_and_prereleases(self):
        releases = [{'tag_name': 'v0.17.1', 'published_at': '2026-10-01T00:00:00Z'},
                    {'tag_name': 'v0.17.6', 'published_at': '2026-10-02T00:00:00Z', 'draft': True},
                    {'tag_name': 'v0.18.0', 'published_at': '2026-10-03T00:00:00Z', 'prerelease': True}]
        r.check_published_base({'previous_release': 'v0.17.1'}, releases, 'v1.0.0')
        with self.assertRaises(r.ReleaseError): r.check_published_base({'previous_release': 'v0.16.3'}, releases, 'v1.0.0')
        releases.append({'tag_name': 'v1.0.0', 'published_at': '2026-10-04T00:00:00Z'})
        r.check_published_base({'previous_release': 'v0.17.1'}, releases, 'v1.0.0')

    def test_notes_range_rejects_future_duplicate_unordered_and_invalid_versions(self):
        for versions in [['1.1.0', '1.1.0'], ['1.2.0', '1.1.0'], ['1.1.0', '1.2.0'], [None], [{'version': '1.1.0'}]]:
            plan = {'previous_release': 'v1.0.0', 'included_versions': versions}
            with self.assertRaises(r.ReleaseError): r.validate_notes_range(plan, '1.1.0', '', '## 1.1.0\n')

    def test_first_release_needs_no_previous_published_tag(self):
        plan = {'previous_release': None, 'included_versions': ['0.1.0']}
        r.check_published_base(plan, [], 'v0.1.0')
        r.validate_notes_range(plan, '0.1.0', '# Tile Launcher 0.1.0\n업데이트 범위: **첫 공개 → v0.1.0**\n### 0.1.0\n- initial functionality\n', '## 0.1.0\n')

    def test_refresh_notes_refuses_to_modify_an_existing_release_or_draft(self):
        args = type('Args', (), {'output': Path('/tmp/unused')})()
        manifest = {'local_only': False, 'config': {'version': '1.1.0'}}
        with mock.patch.object(r, 'verify', return_value=manifest), mock.patch.object(r, 'run', return_value=''), mock.patch.object(r, 'current_notes', return_value=('notes', {})), mock.patch.object(r, 'list_releases', return_value=[{'tag_name': 'v1.1.0', 'draft': True}]):
            with self.assertRaises(r.ReleaseError): r.refresh_notes(args)

    def test_refresh_notes_refuses_a_different_artifact_version(self):
        args = type('Args', (), {'output': Path('/tmp/unused')})()
        manifest = {'local_only': False, 'config': {'version': '0.17.6'}}
        with mock.patch.object(r, 'verify', return_value=manifest), mock.patch.object(r, 'run', return_value=''), mock.patch.object(r, 'current_notes', return_value=('notes', {})), mock.patch.object(r, 'config', return_value={'version': '1.1.0'}), mock.patch.object(r, 'list_releases') as listing:
            with self.assertRaises(r.ReleaseError): r.refresh_notes(args)
            listing.assert_not_called()

    def test_refresh_notes_changes_only_description_files_and_preserves_originals(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            originals = {'notes-source.md': b'old source', 'release-notes.md': b'old description', 'manifest.json': b'old manifest',
                         'app.zip': b'signed zip', 'release-metadata.json': b'metadata', 'SHA256SUMS.txt': b'checksums'}
            for name, data in originals.items(): (root / name).write_bytes(data)
            args = type('Args', (), {'output': root})()
            manifest = {'local_only': False, 'config': {'version': '1.1.0'}, 'signing': 'notarized'}
            plan = {'previous_release': 'v1.0.0', 'included_versions': ['1.1.0']}
            with mock.patch.object(r, 'verify', return_value=manifest), mock.patch.object(r, 'run', side_effect=['', 'a' * 40]), mock.patch.object(r, 'current_notes', return_value=('reviewed changes', plan)), mock.patch.object(r, 'list_releases', return_value=[{'tag_name': 'v1.0.0', 'published_at': '2026-10-01T00:00:00Z'}]), mock.patch.object(r, 'archive') as archive, mock.patch('builtins.print'):
                r.refresh_notes(args)
                archive.assert_not_called()
            for name in ['app.zip', 'release-metadata.json', 'SHA256SUMS.txt']:
                self.assertEqual((root / name).read_bytes(), originals[name])
            saved = json.loads((root / 'manifest.json').read_text())
            self.assertEqual(saved['notes_range'], plan)
            self.assertEqual(saved['notes_revision'], 'a' * 40)
            self.assertEqual(saved['notes_sha256'], r.digest(root / 'release-notes.md'))
            backup = next((root / 'notes-history').iterdir())
            for name in ['notes-source.md', 'release-notes.md', 'manifest.json']:
                self.assertEqual((backup / name).read_bytes(), originals[name])

    def test_failed_description_refresh_restores_all_prior_description_files(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            originals = {name: ('original ' + name).encode() for name in ['notes-source.md', 'release-notes.md', 'manifest.json']}
            for name, data in originals.items(): (root / name).write_bytes(data)
            args = type('Args', (), {'output': root})()
            manifest = {'local_only': False, 'config': {'version': '1.1.0'}, 'signing': 'notarized'}
            plan = {'previous_release': 'v1.0.0', 'included_versions': ['1.1.0']}
            with mock.patch.object(r, 'verify', side_effect=[manifest, r.ReleaseError('verification failed')]), mock.patch.object(r, 'run', side_effect=['', 'a' * 40]), mock.patch.object(r, 'current_notes', return_value=('new source', plan)), mock.patch.object(r, 'list_releases', return_value=[{'tag_name': 'v1.0.0', 'published_at': '2026-10-01T00:00:00Z'}]):
                with self.assertRaises(r.ReleaseError): r.refresh_notes(args)
            for name, data in originals.items(): self.assertEqual((root / name).read_bytes(), data)

    def test_signing_output_rejects_synced_folders(self):
        for folder in ['Desktop', 'Documents', 'Library/Mobile Documents', 'Library/CloudStorage']:
            with self.assertRaises(r.ReleaseError): r.validate_output_path((Path.home() / folder / 'release').resolve())
        r.validate_output_path(Path('/private/tmp/tile-release'))
        r.validate_output_path(Path.home() / 'Library/Developer/TileLauncher/releases/v0.2.0')

    def test_regular_release_configuration_is_consistent(self):
        cfg = r.config()
        self.assertTrue((r.ROOT / 'release/notes.md').read_text().startswith('# Tile Launcher ' + cfg['version'] + '\n'))
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

    def test_release_lookup_finds_draft_on_later_page(self):
        draft = {'id': 42, 'tag_name': 'v0.16.3', 'draft': True}
        pages = [[{'id': 1, 'tag_name': 'v0.1.0', 'draft': False}], [draft]]
        with mock.patch.object(r, 'run', return_value=json.dumps(pages)) as run:
            self.assertEqual(r.find_release('v0.16.3'), draft)
            self.assertIn('--paginate', run.call_args[0][0])
            self.assertIsNone(r.find_release('v9.9.9'))

    def test_release_lookup_rejects_duplicates_and_malformed_listing(self):
        draft = {'id': 42, 'tag_name': 'v0.16.3', 'draft': True}
        for pages in [[draft], [[draft], [dict(draft, id=43)]]]:
            with mock.patch.object(r, 'run', return_value=json.dumps(pages)):
                with self.assertRaises(r.ReleaseError): r.find_release('v0.16.3')

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
