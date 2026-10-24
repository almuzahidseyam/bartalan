"""Create/reuse a private local CA and a server certificate. Requires OpenSSL."""
import ipaddress
import os
from pathlib import Path
import secrets
import shutil
import subprocess
import tempfile
from urllib.parse import urlparse

ROOT = Path(__file__).resolve().parents[1]
TLS = ROOT / '.secrets/tls'


def openssl(*args, check=True):
    result = subprocess.run(['openssl', *map(str, args)], capture_output=True, text=True)
    if check and result.returncode:
        raise RuntimeError('Certificate operation failed: ' + result.stderr[-1200:])
    return result


def main():
    values = dict(line.split('=', 1) for line in (ROOT / '.env').read_text().splitlines()
                  if line and not line.startswith('#'))
    url = urlparse(values['SITE_URL'])
    if url.scheme != 'https' or not url.hostname:
        raise RuntimeError('SITE_URL must use https before generating certificates.')
    hosts = sorted({url.hostname, 'localhost', '127.0.0.1'})
    sans = []
    for host in hosts:
        try:
            ipaddress.ip_address(host)
            kind = 'IP'
        except ValueError:
            kind = 'DNS'
            if not all(c.isalnum() or c in '.-' for c in host):
                raise RuntimeError('Invalid certificate hostname.')
        sans.append(f'{kind}:{host}')
    TLS.mkdir(parents=True, exist_ok=True, mode=0o700)
    os.umask(0o077)
    ca_key, ca_cert = TLS / 'ca.key', TLS / 'ca.crt'
    if ca_key.exists() != ca_cert.exists():
        raise RuntimeError('Incomplete CA: restore the matching CA files; do not silently replace device trust.')
    if not ca_key.exists():
        openssl('req', '-x509', '-newkey', 'rsa:3072', '-nodes', '-sha256', '-days', '3650',
                '-subj', '/CN=BartaLAN Local Root CA/O=BartaLAN',
                '-addext', 'basicConstraints=critical,CA:TRUE,pathlen:0',
                '-addext', 'keyUsage=critical,keyCertSign,cRLSign',
                '-keyout', ca_key, '-out', ca_cert)
    openssl('verify', '-CAfile', ca_cert, ca_cert)
    openssl('x509', '-in', ca_cert, '-checkend', str(366 * 86400), '-noout')
    if openssl('pkey', '-in', ca_key, '-pubout').stdout != openssl('x509', '-in', ca_cert, '-pubkey', '-noout').stdout:
        raise RuntimeError('CA key mismatch')
    server_dir = TLS / 'server'
    server_dir.mkdir(exist_ok=True, mode=0o700)
    server_key, server_cert = server_dir / 'server.key', server_dir / 'server.crt'
    reusable = server_key.exists() and server_cert.exists()
    if reusable:
        checks = [openssl('verify', '-CAfile', ca_cert, server_cert, check=False).returncode == 0,
                  openssl('x509', '-in', server_cert, '-checkend', str(30 * 86400), '-noout', check=False).returncode == 0,
                  openssl('pkey', '-in', server_key, '-pubout').stdout == openssl('x509', '-in', server_cert, '-pubkey', '-noout').stdout]
        for host in hosts:
            try:
                ipaddress.ip_address(host)
                option = '-verify_ip'
            except ValueError:
                option = '-verify_hostname'
            checks.append(openssl('verify', '-CAfile', ca_cert, option, host, server_cert, check=False).returncode == 0)
        reusable = all(checks)
    if not reusable:
        with tempfile.TemporaryDirectory(dir=TLS) as directory:
            work = Path(directory)
            extensions = work / 'extensions.cnf'
            extensions.write_text('basicConstraints=critical,CA:FALSE\n'
                                  'keyUsage=critical,digitalSignature,keyEncipherment\n'
                                  'extendedKeyUsage=serverAuth\n'
                                  'subjectAltName=' + ','.join(sans) + '\n')
            openssl('req', '-new', '-newkey', 'rsa:3072', '-nodes',
                    '-subj', '/CN=BartaLAN Local Server/O=BartaLAN',
                    '-keyout', work / 'server.key', '-out', work / 'server.csr')
            openssl('x509', '-req', '-in', work / 'server.csr', '-CA', ca_cert, '-CAkey', ca_key,
                    '-set_serial', '0x' + secrets.token_hex(16), '-days', '365', '-sha256',
                    '-extfile', extensions, '-out', work / 'server.crt')
            openssl('verify', '-CAfile', ca_cert, work / 'server.crt')
            os.replace(work / 'server.key', server_key)
            os.replace(work / 'server.crt', server_cert)
    public = ROOT / 'certificates'
    public.mkdir(exist_ok=True)
    shutil.copyfile(ca_cert, public / 'BartaLAN-Root-CA.crt')
    openssl('x509', '-in', ca_cert, '-outform', 'DER', '-out', public / 'BartaLAN-Root-CA.cer')
    fingerprint = openssl('x509', '-in', ca_cert, '-noout', '-fingerprint', '-sha256').stdout.strip()
    (public / 'fingerprint.txt').write_text(fingerprint + '\n')
    print('Local HTTPS certificate ready for: ' + ', '.join(hosts))
    print(fingerprint)
    print('Only share certificates/BartaLAN-Root-CA.cer or .crt. Never share .secrets/tls.')


if __name__ == '__main__':
    main()
