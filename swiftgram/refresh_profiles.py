#!/usr/bin/env python3
"""Переподписывает «поддельные» provisioning-профили Swiftgram с новым сроком действия.

Использование: refresh_profiles.py <telegram-ios dir> <out dir>
В out dir появятся certs/ и profiles/ — передать в --codesigningInformationPath.
"""
import os
import shutil
import subprocess
import sys
import tempfile

src_root = os.path.abspath(sys.argv[1])
out = os.path.abspath(sys.argv[2])
sys.path.insert(0, os.path.join(src_root, 'build-system', 'Make'))

import GenerateProfiles as gp  # noqa: E402

fake = os.path.join(src_root, 'build-system', 'fake-codesigning')
certs = os.path.join(fake, 'certs')
p12 = os.path.join(certs, 'SelfSigned.p12')

shutil.rmtree(out, ignore_errors=True)
os.makedirs(os.path.join(out, 'profiles'))
shutil.copytree(certs, os.path.join(out, 'certs'))

cert_data = gp.get_certificate_base64_from_p12(p12, '')
identity = gp.get_signing_identity_from_p12(p12, '')
print('Signing identity:', identity)
keychain = gp.setup_temp_keychain(p12, '')


def run(*args, check=True):
    r = subprocess.run(args, capture_output=True, text=True)
    if check and r.returncode != 0:
        print(r.stdout, r.stderr)
        raise SystemExit('command failed: ' + ' '.join(args))
    return r


try:
    for name in sorted(os.listdir(os.path.join(fake, 'profiles'))):
        if not name.endswith('.mobileprovision'):
            continue
        source = os.path.join(fake, 'profiles', name)
        plist = tempfile.mktemp(suffix='.plist')
        with open(plist, 'w') as f:
            f.write(run('security', 'cms', '-D', '-i', source).stdout)
        while run('plutil', '-remove', 'DeveloperCertificates.0', plist, check=False).returncode == 0:
            pass
        run('plutil', '-insert', 'DeveloperCertificates.0', '-data', cert_data, plist)
        run('plutil', '-remove', 'DER-Encoded-Profile', plist, check=False)
        run('plutil', '-replace', 'CreationDate', '-date', '2026-01-01T00:00:00Z', plist)
        run('plutil', '-replace', 'ExpirationDate', '-date', '2036-01-01T00:00:00Z', plist)
        run('security', 'cms', '-S', '-k', keychain, '-N', identity, '-i', plist,
            '-o', os.path.join(out, 'profiles', name))
        os.unlink(plist)
        print('refreshed', name)
finally:
    gp.cleanup_temp_keychain(keychain)
