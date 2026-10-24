"""Verify real Docker network and published-port boundaries without external requests."""
import json
from pathlib import Path
import subprocess

root=Path(__file__).resolve().parents[1]
compose=['docker','compose','--project-directory',str(root)]
values=dict(line.split('=',1) for line in (root/'.env').read_text().splitlines() if line and not line.startswith('#'))

def output(command):
    return subprocess.check_output(command,text=True).strip()

for service in ['mattermost','postgres']:
    container=output([*compose,'ps','-q',service])
    assert container, f'{service} must be running'
    inspection=json.loads(output(['docker','inspect',container]))[0]
    assert not inspection['HostConfig']['PortBindings'], f'{service} must not publish ports directly'
    networks=inspection['NetworkSettings']['Networks']
    assert len(networks)==1, f'{service} must only join the application network'
    for name in networks:
        network=json.loads(output(['docker','network','inspect',name]))[0]
        assert network['Internal'], f'{service} network must be internal'
        assert not network['EnableIPv6'], 'Review IPv6 isolation before enabling it'
    # Mattermost's production image can be distroless. Inspect its real network
    # namespace using the already cached database image, without adding tools to it.
    routes=output(['docker','run','--rm','--pull=never','--read-only','--cap-drop=ALL',
                  '--network',f'container:{container}','--entrypoint','cat',values['POSTGRES_IMAGE'],'/proc/net/route'])
    assert all(line.split()[1]!='00000000' for line in routes.splitlines()[1:]), f'{service} has an external default route'
    print(f'PASS {service}: internal network only, no external default route, no published ports')

gateway=output([*compose,'ps','-q','gateway'])
inspection=json.loads(output(['docker','inspect',gateway]))[0]
assert set(inspection['HostConfig']['PortBindings'])=={'8080/tcp'}, 'Only the HTTP gateway should publish a port'
assert len(inspection['NetworkSettings']['Networks'])==2, 'Gateway must connect ingress to the application network'
print('PASS gateway: a single published HTTP port; application/database remain isolated')
