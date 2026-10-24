"""Create a local administrator once; credentials stay outside version control."""
import json
import os
from pathlib import Path
import secrets
import subprocess
import sys
import time
import urllib.request
import urllib.error

ROOT = Path(__file__).resolve().parents[1]
credential_path = ROOT / '.secrets' / 'admin.json'

def local(*args):
    command = ['docker', 'compose', '--project-directory', str(ROOT), 'exec', '-T',
               'mattermost', '/mattermost/bin/mmctl', '--local', *args]
    result = subprocess.run(command, capture_output=True, text=True)
    if result.returncode:
        # Never echo the command because it can contain a password.
        raise RuntimeError(result.stderr[-1500:] or result.stdout[-1500:])
    return result.stdout

for attempt in range(120):
    try:
        with urllib.request.urlopen('http://127.0.0.1:8065/api/v4/system/ping', timeout=3) as response:
            if json.load(response).get('status') == 'OK':
                break
    except Exception:
        time.sleep(2)
else:
    raise RuntimeError('Mattermost did not become ready.')

credential_path.parent.mkdir(mode=0o700, exist_ok=True)
if credential_path.exists():
    credentials = json.loads(credential_path.read_text(encoding='utf-8'))
else:
    credentials = {'username': 'bartalan-admin', 'email': 'admin@bartalan.invalid',
                   'password': secrets.token_urlsafe(27), 'team': 'bartalan'}
    # Persist first, so an interrupted setup cannot lose an existing account's password.
    credential_path.write_text(json.dumps(credentials, indent=2) + '\n', encoding='utf-8')
    os.chmod(credential_path, 0o600)
try:
    search_output = local('user', 'search', credentials['username'], '--json')
except RuntimeError as error:
    if f"user {credentials['username']} not found" not in str(error):
        raise
    matches = []
else:
    try:
        matches, _ = json.JSONDecoder().raw_decode(search_output.lstrip())
    except json.JSONDecodeError as error:
        raise RuntimeError('Could not interpret the local user lookup; no account was changed.') from error
    if isinstance(matches, dict):
        matches = [matches]
exists = any(user['username'] == credentials['username'] for user in (matches or []))
try:
    if not exists:
        local('user', 'create', '--email', credentials['email'], '--username', credentials['username'],
              '--password', credentials['password'], '--system-admin')
except Exception:
    # Leave the saved credentials for recovery instead of generating a new password.
    print('Administrator setup failed; saved credentials preserved for recovery.', file=sys.stderr)
    raise
def api(path, body=None, token=None):
    headers = {'Content-Type': 'application/json'}
    if token:
        headers['Authorization'] = f'Bearer {token}'
    request = urllib.request.Request('http://127.0.0.1:8065/api/v4' + path,
        data=json.dumps(body).encode() if body is not None else None, headers=headers)
    with urllib.request.urlopen(request, timeout=20) as response:
        return json.load(response), response.headers.get('Token')

try:
    user, token = api('/users/login', {'login_id': credentials['username'], 'password': credentials['password']})
except urllib.error.HTTPError as error:
    raise RuntimeError('Saved administrator credentials cannot sign in. Preserve the file and recover the account locally.') from error
try:
    try:
        team, _ = api('/teams/name/' + credentials['team'], token=token)
    except urllib.error.HTTPError as error:
        if error.code != 404:
            raise
        team, _ = api('/teams', {'name': credentials['team'], 'display_name': 'BartaLAN', 'type': 'I'}, token)
    try:
        api(f"/teams/{team['id']}/members/{user['id']}", token=token)
    except urllib.error.HTTPError as error:
        if error.code != 404:
            raise
        api(f"/teams/{team['id']}/members", {'team_id': team['id'], 'user_id': user['id']}, token)
finally:
    api('/users/logout', {}, token)
print('Administrator and BartaLAN team are ready. Credentials: .secrets/admin.json')
