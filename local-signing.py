#!/usr/bin/env python3
"""Sign this personal app with a persistent identity in its own local keychain.

No system trust settings or existing signing identities are changed. The keychain
and its password live outside the source tree with permissions limited to its owner.
"""
import os
import pathlib
import secrets
import shlex
import subprocess
import sys
import tempfile


def run(arguments, label, capture=False):
    result = subprocess.run(arguments, stdout=subprocess.PIPE if capture else subprocess.DEVNULL,
                            stderr=subprocess.PIPE, text=True)
    if result.returncode:
        # Do not include command arguments; keychain commands contain credentials.
        detail = result.stderr.strip() if label in ('Import dedicated signing identity', 'Sign Docklet') else ''
        raise RuntimeError(f"{label} failed (exit {result.returncode}). {detail}")
    return result.stdout if capture else None


def sign(app):
    directory = pathlib.Path.home() / 'Library/Application Support/Docklet/Signing'
    directory.mkdir(parents=True, exist_ok=True, mode=0o700)
    directory.chmod(0o700)
    keychain = directory / 'docklet.keychain-db'
    password_file = directory / 'keychain-password'
    certificate = directory / 'certificate.pem'
    if keychain.exists() and (not password_file.exists() or not certificate.exists()):
        raise RuntimeError('The Docklet signing identity is incomplete. Preserve the existing keychain before repairing it.')
    if not keychain.exists():
        password = secrets.token_hex(32)
        descriptor = os.open(password_file, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
        with os.fdopen(descriptor, 'w') as file:
            file.write(password)
        original = shlex.split(run(['/usr/bin/security', 'list-keychains', '-d', 'user'], 'Read keychain search list', capture=True))
        try:
            run(['/usr/bin/security', 'create-keychain', '-p', password, str(keychain)], 'Create dedicated signing keychain')
            run(['/usr/bin/security', 'unlock-keychain', '-p', password, str(keychain)], 'Unlock new signing keychain')
            with tempfile.TemporaryDirectory(prefix='identity-', dir=directory) as temporary:
                temporary = pathlib.Path(temporary)
                config = temporary / 'certificate.conf'
                private_key = temporary / 'private-key.pem'
                archive = temporary / 'identity.p12'
                config.write_text('[req]\nprompt=no\ndistinguished_name=dn\nx509_extensions=extensions\n'
                                  '[dn]\nCN=Docklet Personal Development\n'
                                  '[extensions]\nbasicConstraints=critical,CA:FALSE\n'
                                  'keyUsage=critical,digitalSignature\nextendedKeyUsage=codeSigning\n'
                                  'subjectKeyIdentifier=hash\n')
                run(['/usr/bin/openssl', 'req', '-new', '-newkey', 'rsa:2048', '-nodes', '-x509', '-days', '3650',
                     '-config', str(config), '-keyout', str(private_key), '-out', str(certificate)], 'Create personal signing certificate')
                private_key.chmod(0o600)
                run(['/usr/bin/openssl', 'pkcs12', '-export', '-inkey', str(private_key), '-in', str(certificate),
                     '-name', 'Docklet Personal Development', '-out', str(archive), '-passout', f'file:{password_file}',
                     '-certpbe', 'PBE-SHA1-3DES', '-keypbe', 'PBE-SHA1-3DES', '-macalg', 'sha1'], 'Prepare signing identity')
                archive.chmod(0o600)
                run(['/usr/bin/security', 'import', str(archive), '-k', str(keychain), '-P', password, '-T', '/usr/bin/codesign'], 'Import dedicated signing identity')
                run(['/usr/bin/security', 'set-key-partition-list', '-S', 'apple-tool:,apple:', '-s', '-k', password, str(keychain)], 'Allow signing tools in dedicated keychain')
        except Exception:
            # Only this newly created, incomplete identity is rolled back.
            subprocess.run(['/usr/bin/security', 'delete-keychain', str(keychain)], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            password_file.unlink(missing_ok=True)
            certificate.unlink(missing_ok=True)
            raise
        finally:
            run(['/usr/bin/security', 'list-keychains', '-d', 'user', '-s', *original], 'Restore original keychain search list')
    password_file.chmod(0o600)
    password = password_file.read_text().strip()
    run(['/usr/bin/security', 'unlock-keychain', '-p', password, str(keychain)], 'Unlock dedicated signing identity')
    run(['/usr/bin/security', 'set-keychain-settings', '-lut', '21600', str(keychain)], 'Set dedicated keychain timeout')
    fingerprint = run(['/usr/bin/openssl', 'x509', '-in', str(certificate), '-noout', '-fingerprint', '-sha1'], 'Read certificate fingerprint', capture=True)
    fingerprint = fingerprint.strip().split('=')[-1].replace(':', '')
    if len(fingerprint) != 40 or any(c not in '0123456789ABCDEFabcdef' for c in fingerprint):
        raise RuntimeError('Invalid signing certificate fingerprint.')
    requirement = f'designated => identifier "app.personal.docklet" and certificate leaf = H"{fingerprint}"'
    run(['/usr/bin/xattr', '-cr', str(app)], 'Remove bundle metadata before signing')
    original = shlex.split(run(['/usr/bin/security', 'list-keychains', '-d', 'user'], 'Read keychain search list', capture=True))
    try:
        # codesign still uses the user search list when resolving a private identity,
        # even when --keychain is supplied. Restore the list immediately afterward.
        run(['/usr/bin/security', 'list-keychains', '-d', 'user', '-s', *original, str(keychain)], 'Make dedicated identity available for signing')
        run(['/usr/bin/codesign', '--force', '--sign', 'Docklet Personal Development', '--keychain', str(keychain), '--timestamp=none', '-r', '=' + requirement, str(app)], 'Sign Docklet')
    finally:
        run(['/usr/bin/security', 'list-keychains', '-d', 'user', '-s', *original], 'Restore original keychain search list')
    run(['/usr/bin/codesign', '--verify', '--strict', str(app)], 'Validate signed Docklet')
    print('Docklet signed with its persistent personal development identity.')


if __name__ == '__main__':
    try:
        sign(pathlib.Path(sys.argv[1]).resolve())
    except Exception as error:
        print(str(error), file=sys.stderr)
        sys.exit(1)
