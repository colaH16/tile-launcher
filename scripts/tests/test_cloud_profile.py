import hashlib
import importlib.util
from datetime import datetime, timedelta, timezone
from pathlib import Path
import unittest

SPEC = importlib.util.spec_from_file_location('cloud_release', Path(__file__).parents[1] / 'release.py')
r = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(r)


class CloudProfileTests(unittest.TestCase):
    def profile(self):
        team = 'ABCDEFGHIJ'
        return {
            'ExpirationDate': datetime.now(timezone.utc) + timedelta(days=10),
            'ProvisionsAllDevices': True,
            'TeamIdentifier': [team],
            'DeveloperCertificates': [b'public-test-certificate'],
            'Entitlements': {
                'com.apple.application-identifier': team + '.' + r.BUNDLE_ID,
                'com.apple.developer.team-identifier': team,
                'com.apple.developer.icloud-container-identifiers': ['iCloud.' + r.BUNDLE_ID],
                'com.apple.developer.icloud-services': ['CloudKit'],
                'com.apple.developer.icloud-container-environment': 'Production',
                'com.apple.developer.aps-environment': 'production',
            },
        }

    def test_matching_developer_id_profile_authorizes_only_expected_services(self):
        profile = self.profile()
        value = r.cloud_entitlements(profile, 'ABCDEFGHIJ', hashlib.sha1(b'public-test-certificate').hexdigest())
        self.assertEqual(value['com.apple.developer.aps-environment'], 'production')
        self.assertNotIn('get-task-allow', value)
        self.assertEqual(value['com.apple.developer.icloud-container-identifiers'], ['iCloud.' + r.BUNDLE_ID])

    def test_expired_device_limited_and_other_team_profiles_are_rejected(self):
        for change in [{'ExpirationDate': datetime(2020, 1, 1)}, {'ProvisionsAllDevices': False},
                       {'ProvisionedDevices': ['test-device']}, {'TeamIdentifier': ['OTHERTEAM0']}]:
            profile = self.profile(); profile.update(change)
            with self.subTest(change=change), self.assertRaises(r.ReleaseError):
                r.cloud_entitlements(profile, 'ABCDEFGHIJ')

    def test_wrong_app_container_environment_and_debug_permission_are_rejected(self):
        for key, value in [('com.apple.application-identifier', 'ABCDEFGHIJ.other.app'),
                           ('com.apple.developer.icloud-container-identifiers', ['iCloud.other.app']),
                           ('com.apple.developer.aps-environment', 'development'),
                           ('com.apple.security.get-task-allow', True)]:
            profile = self.profile(); profile['Entitlements'][key] = value
            with self.subTest(key=key), self.assertRaises(r.ReleaseError):
                r.cloud_entitlements(profile, 'ABCDEFGHIJ')

    def test_certificate_not_in_profile_is_rejected(self):
        with self.assertRaises(r.ReleaseError):
            r.cloud_entitlements(self.profile(), 'ABCDEFGHIJ', '0' * 40)

    def test_profile_listing_allowed_container_environments_is_accepted(self):
        # Apple profiles list permitted environments; signing still uses Production only.
        profile = self.profile()
        profile['Entitlements']['com.apple.developer.icloud-container-environment'] = ['Development', 'Production']
        value = r.cloud_entitlements(profile, 'ABCDEFGHIJ')
        self.assertEqual(value['com.apple.developer.icloud-container-environment'], 'Production')
        profile['Entitlements']['com.apple.developer.icloud-container-environment'] = ['Development']
        with self.assertRaises(r.ReleaseError):
            r.cloud_entitlements(profile, 'ABCDEFGHIJ')

    def test_signing_identity_must_be_a_certificate_hash(self):
        with self.assertRaises(r.ReleaseError):
            r.cloud_entitlements(self.profile(), 'ABCDEFGHIJ', 'Developer ID Application: Example (ABCDEFGHIJ)')