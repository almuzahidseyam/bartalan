"""Take a quiesced local backup. Run inside the BartaLAN WSL runtime."""
import datetime
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import sys

root=Path(__file__).resolve().parents[1]
compose=['docker','compose','--project-directory',str(root)]
values=dict(line.split('=',1) for line in (root/'.env').read_text().splitlines() if line and not line.startswith('#'))
destination=root/'backups'/datetime.datetime.now(datetime.timezone.utc).strftime('%Y%m%dT%H%M%S%fZ')
destination.mkdir(parents=True,mode=0o700)

def run(*args,**kwargs):
    return subprocess.run([*compose,*args],check=True,**kwargs)

container_id=subprocess.check_output([*compose,'ps','-q','mattermost'],text=True).strip()
if not container_id: raise RuntimeError('Start the server before taking a backup.')
inspection=json.loads(subprocess.check_output(['docker','inspect',container_id]))[0]
was_running=inspection['State']['Running']
mounts={mount['Destination']:mount['Name'] for mount in inspection['Mounts'] if mount['Type']=='volume'}
try:
    run('stop','mattermost')
    with (destination/'database.dump').open('wb') as output:
        run('exec','-T','postgres','pg_dump','-U',values['POSTGRES_USER'],'-d',values['POSTGRES_DB'],'-Fc',stdout=output)
    for name,path in [('config','/mattermost/config'),('files','/mattermost/data')]:
        subprocess.run(['docker','run','--rm','--pull=never','--network','none',
            '--mount',f'type=volume,src={mounts[path]},dst=/source,readonly',
            '--mount',f'type=bind,src={destination},dst=/backup',
            '--entrypoint','tar',values['POSTGRES_IMAGE'],'-czf',f'/backup/{name}.tar.gz','-C','/source','.'],check=True)
    shutil.copy2(root/'.env',destination/'server.env')
    if (root/'.secrets/admin.json').exists(): shutil.copy2(root/'.secrets/admin.json',destination/'admin.json')
    if (root/'.secrets/tls').exists(): shutil.copytree(root/'.secrets/tls',destination/'tls')
    def checksum(path):
        with path.open('rb') as source:
            return hashlib.file_digest(source,'sha256').hexdigest()
    manifest={'format':2,'created_at':datetime.datetime.now(datetime.timezone.utc).isoformat(),
              'images':{key:values[key] for key in ['MATTERMOST_IMAGE','POSTGRES_IMAGE','GATEWAY_IMAGE']},
              'sha256':{p.relative_to(destination).as_posix():checksum(p) for p in destination.rglob('*') if p.is_file()}}
    (destination/'manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')
    print(f'Backup complete: {destination.name}. Contains private data and secrets.')
finally:
    if was_running: run('start','mattermost')
