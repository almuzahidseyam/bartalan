"""Verify TLS trust/hostname boundaries and actual HTTP account throttling."""
import concurrent.futures
import json
from pathlib import Path
import secrets
import socket
import ssl
import sys
import urllib.error
import urllib.request

root = Path(__file__).resolve().parents[1]
values = dict(line.split('=', 1) for line in (root / '.env').read_text().splitlines()
              if line and not line.startswith('#'))
port = int(values['APP_PORT'])
context = ssl.create_default_context(cafile=str(root / '.secrets/tls/ca.crt'))


def handshake(ctx, hostname='localhost'):
    with socket.create_connection(('127.0.0.1', port), timeout=5) as connection:
        with ctx.wrap_socket(connection, server_hostname=hostname) as secured:
            return secured.version()


assert handshake(context) in ('TLSv1.2', 'TLSv1.3')
print('PASS trusted TLS handshake')
for ctx, hostname, label in [(ssl.create_default_context(), 'localhost', 'untrusted CA'),
                              (context, 'wrong-host.invalid', 'wrong hostname')]:
    try:
        handshake(ctx, hostname)
    except ssl.SSLCertVerificationError:
        print(f'PASS {label} rejected')
    else:
        raise AssertionError(f'{label} unexpectedly accepted')
legacy = ssl.SSLContext(ssl.PROTOCOL_TLS_CLIENT)
legacy.check_hostname = False
legacy.verify_mode = ssl.CERT_NONE
legacy.minimum_version = ssl.TLSVersion.TLSv1
legacy.maximum_version = ssl.TLSVersion.TLSv1_1
legacy.set_ciphers('ALL:@SECLEVEL=0')
try:
    handshake(legacy)
except ssl.SSLError:
    print('PASS obsolete TLS versions rejected')
else:
    raise AssertionError('Obsolete TLS accepted')
with urllib.request.urlopen(f'https://127.0.0.1:{port}/api/v4/system/ping', context=context, timeout=5) as response:
    assert response.headers['X-Content-Type-Options'] == 'nosniff'
    assert json.load(response)['status'] == 'OK'
print('PASS HTTPS health and response security headers')

if '--rate-limit' in sys.argv:
    suffix = secrets.token_hex(5)

    def attempt(index):
        # Invalid passwords never create accounts or lock out real users.
        payload = {'username': f'limit-{suffix}-{index}', 'email': f'limit-{suffix}-{index}@bartalan.invalid', 'password': 'short'}
        request = urllib.request.Request(f'https://127.0.0.1:{port}/api/v4/users',
            data=json.dumps(payload).encode(), headers={'Content-Type': 'application/json'})
        try:
            with urllib.request.urlopen(request, context=context, timeout=10) as response:
                return response.status
        except urllib.error.HTTPError as error:
            return error.code

    with concurrent.futures.ThreadPoolExecutor(max_workers=8) as executor:
        codes = list(executor.map(attempt, range(40)))
    assert 429 in codes, f'Expected signup throttling, received {set(codes)}'
    assert all(code in (400, 429) for code in codes), set(codes)
    print('PASS excessive signup attempts return HTTP 429; no accounts created')
