#!/usr/bin/env python3
"""Local release preparation. Never installs or launches the production app.

prepare -> sign (optional) -> notarize (optional) -> verify -> draft -> publish
Unsigned releases require --allow-unnotarized at each GitHub mutation.
Credentials stay in Keychain/gh; this tool never accepts passwords or private keys.
"""
import argparse
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import platform
import plistlib
import re
import shutil
import stat
import subprocess
import sys
import tempfile
import zipfile

ROOT = Path(__file__).resolve().parents[1]
REPOSITORY = 'colaH16/tile-launcher'
BUNDLE_ID = 'dev.cola16.TileLauncher'
APP = 'Tile Launcher.app'


class ReleaseError(Exception):
    pass


def require(value, message):
    if not value:
        raise ReleaseError(message)


def run(args, cwd=ROOT, env=None, log_path=None):
    result = subprocess.run(list(map(str, args)), cwd=cwd, env=env, capture_output=True, text=True)
    if log_path:
        Path(log_path).write_text(result.stdout + result.stderr)
    if result.returncode:
        raise ReleaseError(f'{args[0]} failed ({result.returncode}):\n{result.stdout}\n{result.stderr}')
    return result.stdout.strip()


def digest(path):
    h = hashlib.sha256()
    with Path(path).open('rb') as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b''):
            h.update(chunk)
    return h.hexdigest()


def tree_digest(root):
    h = hashlib.sha256()
    for path in sorted(Path(root).rglob('*')):
        require(not path.is_symlink(), 'Unexpected symlink inside app bundle.')
        if path.is_file():
            h.update(str(path.relative_to(root)).encode() + b'\0')
            h.update(str(stat.S_IMODE(path.stat().st_mode)).encode() + b'\0')
            h.update(digest(path).encode())
    return h.hexdigest()


def write_json(path, value):
    temporary = Path(str(path) + '.tmp')
    temporary.write_text(json.dumps(value, ensure_ascii=False, indent=2) + '\n')
    temporary.replace(path)


def config():
    value = json.loads((ROOT / 'release/config.json').read_text())
    require(re.fullmatch(r'(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)', value['version']), 'Invalid numeric version.')
    require(re.fullmatch(r'[1-9]\d*', value['build']), 'Invalid build number.')
    require(value['architecture'] == 'arm64' and value['minimum_macos'] == '26.0', 'Review platform support before changing release targets.')
    require(value['prerelease'] is False, 'The user selected a regular release.')
    return value


def load(output):
    value = json.loads((output / 'manifest.json').read_text())
    require(value['signing'] in ['adhoc', 'developer-id', 'notarized'] and type(value['local_only']) is bool, 'Invalid signing/local-only state.')
    require(value['repository'] == REPOSITORY and value['config'] == config(), 'Release configuration differs from prepared artifact.')
    require(re.fullmatch(r'[a-f0-9]{40}', value['source_revision']), 'Invalid source revision.')
    return value


def app_path(output):
    return output / 'products' / APP


def check_bundle(bundle, manifest, developer_id=False):
    cfg = manifest['config']
    require(manifest['signing'] in ['adhoc', 'developer-id', 'notarized'], 'Unknown signing state.')
    info = plistlib.loads((bundle / 'Contents/Info.plist').read_bytes())
    expected = {'CFBundleIdentifier': BUNDLE_ID, 'CFBundleShortVersionString': cfg['version'],
                'CFBundleVersion': cfg['build'], 'LSMinimumSystemVersion': cfg['minimum_macos'],
                'TileLauncherSourceRevision': manifest['source_revision']}
    require(all(info.get(k) == v for k, v in expected.items()), 'Bundle metadata/version/source does not match manifest.')
    binary = bundle / 'Contents/MacOS/TileLauncher'
    require(os.access(binary, os.X_OK), 'App executable lost its executable permission.')
    require(run(['/usr/bin/lipo', '-archs', binary]) == cfg['architecture'], 'Unexpected executable architecture.')
    require((bundle / 'Contents/Resources/AppIcon.icns').is_file(), 'App icon missing.')
    metadata = json.loads((bundle / 'Contents/Resources/Metadata.appintents/extract.actionsdata').read_text())
    require('LauncherFocusIntent' in metadata['actions'] and 'ProfileEntity' in metadata['entities'], 'Focus metadata missing.')
    run(['/usr/bin/codesign', '--verify', '--deep', '--strict', bundle])
    details = subprocess.run(['/usr/bin/codesign', '-dv', '--verbose=4', str(bundle)], capture_output=True, text=True)
    require(details.returncode == 0, 'Cannot inspect code signature.')
    if developer_id:
        text = details.stderr
        require('Authority=Developer ID Application:' in text, 'Not a Developer ID Application signature.')
        require('TeamIdentifier=' + manifest['team_id'] in text, 'Signing team mismatch.')
        require('(runtime)' in text and 'Timestamp=' in text, 'Hardened runtime or secure timestamp missing.')
        entitlements = run(['/usr/bin/codesign', '-d', '--entitlements', ':-', bundle])
        parsed = plistlib.loads(entitlements.encode()) if entitlements else {}
        require(parsed == {'com.apple.security.automation.apple-events': True}, 'Unexpected release entitlements.')
    else:
        require('Signature=adhoc' in details.stderr, 'Expected development ad-hoc signing.')
    return info


def archive(output, manifest):
    bundle = app_path(output)
    downloads = output / 'downloads'
    downloads.mkdir(exist_ok=True)
    status = manifest['signing']
    suffix = '' if status == 'notarized' else '-unnotarized'
    name = f"Tile-Launcher-{manifest['config']['version']}-arm64{suffix}.zip"
    destination = downloads / name
    # Repacking a known output is intentional; unrelated files are never glob-uploaded.
    if destination.exists():
        destination.unlink()
    run(['/usr/bin/ditto', '-c', '-k', '--sequesterRsrc', '--keepParent', bundle, destination])
    public = {key: manifest[key] for key in ['repository', 'config', 'source_revision', 'signing', 'local_only', 'toolchain']}
    public['archive'] = name
    public['archive_sha256'] = digest(destination)
    write_json(downloads / 'release-metadata.json', public)
    manifest['assets'] = {name: digest(destination), 'release-metadata.json': digest(downloads / 'release-metadata.json')}
    checksums = ''.join(f'{sha}  {name}\n' for name, sha in manifest['assets'].items())
    (downloads / 'SHA256SUMS.txt').write_text(checksums)
    manifest['assets']['SHA256SUMS.txt'] = digest(downloads / 'SHA256SUMS.txt')
    manifest['bundle_sha256'] = tree_digest(bundle)
    write_json(output / 'manifest.json', manifest)
    status_text = ('**Developer ID 서명 및 Apple 공증 완료.**' if status == 'notarized' else
                   '**Apple 공증 없음. 개발용 ad-hoc 서명입니다.**' if status == 'adhoc' else
                   '**Developer ID 서명 완료, Apple 공증은 아직 받지 않았습니다.**')
    warning = '' if status == 'notarized' else '\n첫 실행이 차단되면 신뢰하는 원본 파일인지 확인한 후 시스템 설정 → 개인정보 보호 및 보안 → 그래도 열기로 허용해야 할 수 있습니다.\n'
    notes = status_text + '\n' + warning + '\n' + (output / 'notes-source.md').read_text()
    (output / 'release-notes.md').write_text(notes)
    manifest['notes_sha256'] = digest(output / 'release-notes.md')
    write_json(output / 'manifest.json', manifest)
    print('Prepared:', destination)


def validate_output_path(output):
    # Desktop/Documents/CloudStorage can add Finder metadata while signing.
    home = Path.home()
    synced = [home / 'Desktop', home / 'Documents', home / 'Library/Mobile Documents', home / 'Library/CloudStorage']
    require(not any(output.is_relative_to(path.resolve()) for path in synced),
            'Build/sign outside synced folders. Use ~/Library/Developer/TileLauncher/releases/v' + config()['version'] + '.')


def prepare(args):
    cfg = config()
    output = args.output
    validate_output_path(output)
    require(not output.exists() or not any(output.iterdir()), 'Output directory is not empty; choose a new directory.')
    dirty = bool(run(['git', 'status', '--porcelain']))
    require(args.local_check or not dirty, 'Commit the release sources first, or use --local-check for non-publishable rehearsal.')
    require(platform.machine() == cfg['architecture'], 'Build on Apple Silicon for this release.')
    revision = run(['git', 'rev-parse', 'HEAD'])
    output.mkdir(parents=True, exist_ok=True)
    (output / 'products').mkdir()
    print('Building isolated release bundle…', flush=True)
    with tempfile.TemporaryDirectory(prefix='tile-release-source-') as temporary:
        source = Path(temporary)
        if args.local_check:
            source = ROOT
        else:
            tar = Path(temporary) / 'source.tar'
            run(['git', 'archive', '--format=tar', '--output', tar, revision])
            run(['/usr/bin/tar', '-xf', tar, '-C', source])
            tar.unlink()
        env = dict(os.environ, TILE_LAUNCHER_OUTPUT_DIR=str(output / 'products'))
        run(['bash', source / 'scripts/build.sh'], cwd=source, env=env, log_path=output / 'build.log')
        shutil.copy2(source / 'release/notes.md', output / 'notes-source.md')
        shutil.copy2(source / 'release/entitlements.plist', output / 'entitlements.plist')
        shutil.copy2(source / 'LICENSE', app_path(output) / 'Contents/Resources/LICENSE.txt')
        shutil.copy2(source / 'docs/installation.md', app_path(output) / 'Contents/Resources/Installation.md')
    bundle = app_path(output)
    plist = bundle / 'Contents/Info.plist'
    info = plistlib.loads(plist.read_bytes())
    info.update(CFBundleShortVersionString=cfg['version'], CFBundleVersion=cfg['build'], TileLauncherSourceRevision=revision)
    info['NSAppleEventsUsageDescription'] = 'Finder의 통합 휴지통을 열기 위해 사용합니다.'
    plist.write_bytes(plistlib.dumps(info))
    run(['/usr/bin/xattr', '-cr', bundle])
    run(['/usr/bin/codesign', '--force', '--sign', '-', bundle])
    manifest = dict(repository=REPOSITORY, config=cfg, source_revision=revision, signing='adhoc',
                    local_only=bool(args.local_check), toolchain=run(['xcodebuild', '-version']),
                    created_at=datetime.now(timezone.utc).isoformat())
    check_bundle(bundle, manifest)
    archive(output, manifest)
    verify(args)


def validate_zip(path):
    with zipfile.ZipFile(path) as zipped:
        require(zipped.testzip() is None, 'ZIP integrity error.')
        for entry in zipped.infolist():
            parts = PurePosixPath(entry.filename).parts
            require(parts and not entry.filename.startswith('/') and '..' not in parts
                    and parts[0] in [APP, '__MACOSX'], 'Unexpected ZIP path.')
            require(not stat.S_ISLNK(entry.external_attr >> 16), 'Unexpected ZIP symlink.')


def verify(args):
    output = args.output
    manifest = load(output)
    bundle = app_path(output)
    require(tree_digest(bundle) == manifest['bundle_sha256'], 'App changed after packaging.')
    check_bundle(bundle, manifest, developer_id=manifest['signing'] != 'adhoc')
    require(digest(output / 'release-notes.md') == manifest['notes_sha256'], 'Release notes changed; prepare again.')
    for name, sha in manifest['assets'].items():
        require(Path(name).name == name and digest(output / 'downloads' / name) == sha, 'Release asset checksum mismatch.')
    archive_name = next(name for name in manifest['assets'] if name.endswith('.zip'))
    path = output / 'downloads' / archive_name
    validate_zip(path)
    with tempfile.TemporaryDirectory(prefix='tile-release-verify-') as temporary:
        run(['/usr/bin/ditto', '-x', '-k', path, temporary])
        extracted = Path(temporary) / APP
        require(tree_digest(extracted) == manifest['bundle_sha256'], 'ZIP does not match verified app.')
        check_bundle(extracted, manifest, developer_id=manifest['signing'] != 'adhoc')
        if manifest['signing'] == 'notarized':
            run(['xcrun', 'stapler', 'validate', extracted])
            run(['/usr/sbin/spctl', '--assess', '--type', 'execute', '--verbose=2', extracted])
    print('Verified:', manifest['signing'], 'local-only' if manifest['local_only'] else manifest['source_revision'][:12])
    return manifest


def sign(args):
    manifest = verify(args)
    require(not manifest['local_only'], 'Local rehearsals cannot be promoted. Prepare from a clean committed source.')
    require(manifest['signing'] == 'adhoc', 'Signing already completed; do not replace an existing signature.')
    require(re.fullmatch('[A-Fa-f0-9]{40}', args.identity or ''), 'Use a Developer ID Application certificate SHA-1, not a password/key.')
    require(re.fullmatch('[A-Z0-9]{10}', args.team_id or ''), 'Invalid Team ID.')
    identities = run(['/usr/bin/security', 'find-identity', '-v', '-p', 'codesigning'])
    require(any(args.identity.lower() in line.lower() and 'Developer ID Application:' in line
                and f'({args.team_id})' in line for line in identities.splitlines()), 'Matching valid Developer ID Application identity not found.')
    manifest['team_id'] = args.team_id
    entitlements = plistlib.loads((args.output / 'entitlements.plist').read_bytes())
    require(entitlements == {'com.apple.security.automation.apple-events': True}, 'Unexpected signing entitlements.')
    with tempfile.TemporaryDirectory(prefix='tile-sign-') as temporary:
        staged = Path(temporary) / APP
        shutil.copytree(app_path(args.output), staged)
        run(['/usr/bin/codesign', '--force', '--sign', args.identity, '--options', 'runtime', '--timestamp',
             '--entitlements', args.output / 'entitlements.plist', staged])
        check_bundle(staged, manifest, developer_id=True)
        previous = args.output / 'pre-sign.app'
        require(not previous.exists(), 'An interrupted signing backup exists; inspect it first.')
        app_path(args.output).rename(previous)
        try:
            shutil.copytree(staged, app_path(args.output))
        except Exception:
            if app_path(args.output).exists(): shutil.rmtree(app_path(args.output))
            previous.rename(app_path(args.output))
            raise
    manifest['signing'] = 'developer-id'
    archive(args.output, manifest)


def notarize(args):
    manifest = verify(args)
    require(not manifest['local_only'] and manifest['signing'] == 'developer-id', 'Developer ID signing is required before notarization.')
    profile = args.keychain_profile
    require(profile and not profile.startswith('-'), 'Provide a Keychain profile name.')
    if args.submission_id:
        require(re.fullmatch(r'[a-fA-F0-9-]{36}', args.submission_id), 'Invalid submission ID.')
        require(manifest.get('notary_pending_submission') is True and not manifest.get('notary_id'), 'Recovery ID is only for an interrupted submission.')
        manifest['notary_id'] = args.submission_id
        write_json(args.output / 'manifest.json', manifest)
    if not manifest.get('notary_id'):
        require(not manifest.get('notary_pending_submission'), 'Previous submission outcome unknown. Inspect notarytool history, then use --submission-id to resume without a duplicate upload.')
        manifest['notary_pending_submission'] = True
        write_json(args.output / 'manifest.json', manifest)
        archive_name = next(name for name in manifest['assets'] if name.endswith('.zip'))
        response = json.loads(run(['xcrun', 'notarytool', 'submit', args.output / 'downloads' / archive_name,
                                   '--keychain-profile', profile, '--no-wait', '--output-format', 'json']))
        require(re.fullmatch(r'[a-fA-F0-9-]{36}', response.get('id', '')), 'No valid submission ID returned; inspect Apple submission history before retrying.')
        manifest['notary_id'] = response['id']
        write_json(args.output / 'manifest.json', manifest)
    response = json.loads(run(['xcrun', 'notarytool', 'info', manifest['notary_id'], '--keychain-profile', profile, '--output-format', 'json']))
    require(response.get('name') == next(name for name in manifest['assets'] if name.endswith('.zip')), 'Submission archive name mismatch.')
    write_json(args.output / 'notary-status.json', response)
    require(response.get('status') in ['Accepted', 'In Progress'],
            'Notarization was rejected. Inspect notarytool log for ' + manifest['notary_id'] + ' before preparing a corrected build.')
    if response.get('status') != 'Accepted':
        print('Notarization:', response.get('status'), manifest['notary_id'])
        print('Run notarize again later to check the same submission. No duplicate upload is made.')
        return
    with tempfile.TemporaryDirectory(prefix='tile-staple-') as temporary:
        staged = Path(temporary) / APP
        shutil.copytree(app_path(args.output), staged)
        run(['xcrun', 'stapler', 'staple', staged])
        run(['xcrun', 'stapler', 'validate', staged])
        run(['/usr/sbin/spctl', '--assess', '--type', 'execute', '--verbose=2', staged])
        # Only replace after all Apple checks pass. Keep the prior app recoverable.
        previous = args.output / 'pre-staple.app'
        require(not previous.exists(), 'An interrupted staple backup exists; inspect it first.')
        app_path(args.output).rename(previous)
        try:
            shutil.copytree(staged, app_path(args.output))
        except Exception:
            if app_path(args.output).exists(): shutil.rmtree(app_path(args.output))
            previous.rename(app_path(args.output))
            raise
    manifest['signing'] = 'notarized'
    archive(args.output, manifest)
    verify(args)


def publication_allowed(manifest, allow_unnotarized):
    require(not manifest['local_only'], 'Local-check artifacts cannot be uploaded.')
    require(manifest['signing'] == 'notarized' or allow_unnotarized,
            'This artifact is not notarized. Use --allow-unnotarized only for an explicitly chosen unnotarized release.')


def find_release(tag):
    # GitHub's by-tag endpoint omits drafts. Listing authenticated releases also
    # prevents a retry from accidentally creating a second draft for this tag.
    pages = json.loads(run(['gh', 'api', f'repos/{REPOSITORY}/releases?per_page=100', '--paginate', '--slurp']))
    require(isinstance(pages, list) and all(isinstance(page, list) for page in pages), 'Invalid release listing.')
    matches = [release for page in pages for release in page if release.get('tag_name') == tag]
    require(len(matches) <= 1, 'Multiple releases use this tag; inspect before continuing.')
    return matches[0] if matches else None


def download_release_assets(release, directory):
    for asset in release['assets']:
        require(isinstance(asset['id'], int), 'Invalid asset ID.')
        # Asset names were checked against the verified local manifest by caller.
        with (Path(directory) / asset['name']).open('wb') as destination:
            result = subprocess.run(['gh', 'api', f'repos/{REPOSITORY}/releases/assets/{asset["id"]}',
                                     '-H', 'Accept: application/octet-stream'], stdout=destination, stderr=subprocess.PIPE)
        require(result.returncode == 0, 'Could not download release asset: ' + asset['name'])


def github(args):
    manifest = verify(args)
    publication_allowed(manifest, args.allow_unnotarized)
    run(['gh', 'auth', 'status'])
    remote = run(['git', 'remote', 'get-url', 'origin'])
    require(remote in [f'git@github.com:{REPOSITORY}.git', f'https://github.com/{REPOSITORY}.git'], 'Unexpected origin repository.')
    repo = json.loads(run(['gh', 'repo', 'view', REPOSITORY, '--json', 'nameWithOwner,visibility']))
    require(repo['nameWithOwner'] == REPOSITORY and repo['visibility'] == 'PUBLIC', 'Expected public repository; visibility is never changed automatically.')
    tag = 'v' + manifest['config']['version']
    revision = manifest['source_revision']
    run(['git', 'fetch', 'origin', 'main', '--no-tags'])
    run(['git', 'merge-base', '--is-ancestor', revision, 'origin/main'])
    remote_tags = run(['git', 'ls-remote', 'origin', 'refs/tags/' + tag, 'refs/tags/' + tag + '^{}'])
    refs = dict(line.split()[::-1] for line in remote_tags.splitlines())
    target = refs.get('refs/tags/' + tag + '^{}', refs.get('refs/tags/' + tag))
    if args.command == 'draft':
        require(find_release(tag) is None, 'A release or draft already exists; nothing overwritten.')
        if target is None:
            local = subprocess.run(['git', 'rev-parse', '--verify', 'refs/tags/' + tag + '^{commit}'], cwd=ROOT, capture_output=True, text=True)
            if local.returncode == 0:
                require(local.stdout.strip() == revision, 'Existing local tag points to another commit.')
            else:
                run(['git', 'tag', '-a', tag, revision, '-m', 'Tile Launcher ' + manifest['config']['version']])
            run(['git', 'push', 'origin', 'refs/tags/' + tag])
        else:
            require(target == revision, 'Remote tag points to another commit.')
        assets = [args.output / 'downloads' / name for name in manifest['assets']]
        print(run(['gh', 'release', 'create', tag, *assets, '--repo', REPOSITORY, '--verify-tag', '--draft',
                   '--prerelease=false', '--title', 'Tile Launcher ' + manifest['config']['version'],
                   '--notes-file', args.output / 'release-notes.md']))
        return
    require(target == revision, 'Remote tag/source mismatch.')
    release = find_release(tag)
    require(release is not None and release['draft'] and not release['prerelease'], 'Expected a regular draft release.')
    require(release['body'].strip() == (args.output / 'release-notes.md').read_text().strip(), 'Draft notes differ from verified notes.')
    require({a['name'] for a in release['assets']} == set(manifest['assets']), 'Draft assets differ from prepared assets.')
    with tempfile.TemporaryDirectory(prefix='tile-release-download-') as temporary:
        download_release_assets(release, temporary)
        require(all(digest(Path(temporary) / name) == sha for name, sha in manifest['assets'].items()), 'Uploaded assets do not match local checksums.')
    require(isinstance(release['id'], int), 'Invalid release ID.')
    published = json.loads(run(['gh', 'api', '--method', 'PATCH', f'repos/{REPOSITORY}/releases/{release["id"]}',
                                '-F', 'draft=false', '-F', 'prerelease=false', '-f', 'make_latest=true']))
    require(published['tag_name'] == tag and not published['draft'] and not published['prerelease'], 'Unexpected publication response; inspect remote state before retrying.')
    print(published['html_url'])


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest='command', required=True)
    for name in ['prepare', 'verify', 'sign', 'notarize', 'draft', 'publish']:
        command = sub.add_parser(name)
        command.add_argument('--output', type=Path, default=Path.home() / 'Library/Developer/TileLauncher/releases' / ('v' + config()['version']))
        if name == 'prepare': command.add_argument('--local-check', action='store_true')
        if name == 'sign':
            command.add_argument('--identity', required=True)
            command.add_argument('--team-id', required=True)
        if name == 'notarize':
            command.add_argument('--keychain-profile', required=True)
            command.add_argument('--submission-id', help='Recover a submission whose result was interrupted.')
        if name in ['draft', 'publish']: command.add_argument('--allow-unnotarized', action='store_true')
    args = parser.parse_args()
    args.output = args.output.expanduser().resolve()
    try:
        {'prepare': prepare, 'verify': verify, 'sign': sign, 'notarize': notarize,
         'draft': github, 'publish': github}[args.command](args)
    except (ReleaseError, OSError, ValueError, KeyError, zipfile.BadZipFile) as error:
        print('Release stopped:', error, file=sys.stderr)
        return 1
    return 0


if __name__ == '__main__':
    sys.exit(main())
