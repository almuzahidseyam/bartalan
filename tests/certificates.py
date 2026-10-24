"""Exercise CA preservation, leaf reuse, address changes, and partial-CA recovery."""
import contextlib
import importlib.util
import io
from pathlib import Path
import tempfile

source = Path(__file__).resolve().parents[1] / 'scripts/certificates.py'
spec = importlib.util.spec_from_file_location('bartalan_certificates', source)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)

with tempfile.TemporaryDirectory() as directory:
    root = Path(directory)
    module.ROOT = root
    module.TLS = root / '.secrets/tls'
    config = root / '.env'
    config.write_text('SITE_URL=https://192.0.2.10:18065\n')
    with contextlib.redirect_stdout(io.StringIO()):
        module.main()
    ca = (module.TLS / 'ca.crt').read_bytes()
    leaf = (module.TLS / 'server/server.crt').read_bytes()
    with contextlib.redirect_stdout(io.StringIO()):
        module.main()
    assert (module.TLS / 'server/server.crt').read_bytes() == leaf, 'Valid leaf must be reused'
    config.write_text('SITE_URL=https://192.0.2.11:18065\n')
    with contextlib.redirect_stdout(io.StringIO()):
        module.main()
    assert (module.TLS / 'ca.crt').read_bytes() == ca, 'Address change must preserve CA trust'
    assert (module.TLS / 'server/server.crt').read_bytes() != leaf, 'Address change must reissue leaf'
    module.openssl('verify', '-CAfile', module.TLS / 'ca.crt', '-verify_ip', '192.0.2.11', module.TLS / 'server/server.crt')
    assert module.openssl('verify', '-CAfile', module.TLS / 'ca.crt', '-verify_ip', '192.0.2.10', module.TLS / 'server/server.crt', check=False).returncode != 0
    (module.TLS / 'ca.crt').unlink()
    try:
        module.main()
    except RuntimeError as error:
        assert 'Incomplete CA' in str(error)
    else:
        raise AssertionError('Partial CA must not be silently replaced')
print('PASS leaf reuse, changed-IP renewal, CA preservation, and partial-CA rejection')
