#!/usr/bin/env bash
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive
if command -v docker >/dev/null && docker compose version >/dev/null 2>&1; then
    systemctl start docker
    exit 0
fi
apt-get update -qq -o APT::Update::Error-Mode=any -o Acquire::Retries=1 -o Acquire::http::Timeout=20 -o Acquire::https::Timeout=20
apt-get install -y -qq ca-certificates curl systemd systemd-sysv dbus procps iproute2 python3
install -m 0755 -d /etc/apt/keyrings
curl --fail --silent --show-error --location https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
chmod a+r /etc/apt/keyrings/docker.asc
cat > /etc/apt/sources.list.d/docker.sources <<'EOF'
Types: deb
URIs: https://download.docker.com/linux/ubuntu
Suites: noble
Components: stable
Architectures: amd64
Signed-By: /etc/apt/keyrings/docker.asc
EOF
apt-get update -qq -o APT::Update::Error-Mode=any -o Acquire::Retries=1 -o Acquire::http::Timeout=20 -o Acquire::https::Timeout=20
apt-get install -y -qq docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
cat > /etc/wsl.conf <<'EOF'
[boot]
systemd=true

[user]
default=root
EOF
install -d -m 0755 /etc/docker
if [ ! -f /etc/docker/daemon.json ]; then
    printf '%s\n' '{"log-driver":"json-file","log-opts":{"max-size":"10m","max-file":"3"}}' > /etc/docker/daemon.json
fi
systemctl enable docker 2>/dev/null || true
echo 'Docker installed. Restart this BartaLAN distribution to start systemd.'
