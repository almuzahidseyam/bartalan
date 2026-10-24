# Network topology and troubleshooting

The initial target is one trusted LAN. A router's Wi-Fi icon means a device has connected to that router, not that it can reach another household's router.

| Scope | Required path | Who controls it |
| --- | --- | --- |
| Same LAN | Client → LAN router/switch → server PC | LAN operator |
| Several homes on one ISP | Client → ISP access network → locally reachable server | ISP plus server operator |
| Different ISPs | Access networks plus working inter-ISP local routing | Participating ISPs |

BDIX or other peering is not a guarantee that a particular subscriber can reach a particular server during an outage. Confirm routing and policy with the ISP and test it. A public IP, port-forwarding rule, VPN, or cloud tunnel alone cannot create a path when the underlying links are down. CGNAT/client isolation may prevent household hosting from working across homes.

## Windows 11 / WSL 2 NAT path

The supplied Windows scripts use a dedicated WSL 2 distribution named `BartaLAN` in the default NAT networking mode. Docker publishes the NGINX gateway at TCP 18065 inside WSL. Windows localhost forwarding provides access from the host PC. LAN access uses a Windows portproxy from the PC's selected LAN IPv4 address to WSL's current IPv4 address, with a firewall rule restricted to the chosen subnet. Mattermost and PostgreSQL are not directly published.

The internal Docker network blocks normal off-network traffic from Mattermost and PostgreSQL. NGINX also joins an ordinary ingress bridge so Docker versions that omit published ports on internal-only networks can accept clients. Its configuration forwards only to Mattermost. This is application isolation, not a firewall for NGINX, the user's PC, or browser. Initial package/image downloads take place outside the application network. The pilot does not alter system-wide sleep settings, router DHCP, NAT settings, Wi-Fi isolation, or other WSL distributions.

## Diagnostics in order

Windows/Hyper-V can reserve TCP port ranges even when no process appears to be listening. A reserved port cannot be used by Windows forwarding. The pilot uses host port 18065; both initialization and LAN setup check Windows's exclusion list and reject a reserved port. If necessary, select a free port, update both `APP_PORT` and `SITE_URL`, restart the stack, and recreate the forwarding entries. Do not delete Windows's reserved ranges to make the application fit.

1. `scripts/Status.ps1`: confirm the services run and localhost health is OK.
2. From the Windows host, open the configured LAN address. If localhost works but LAN does not, check WSL's current IP and the portproxy (`netsh interface portproxy show v4tov4`).
3. Run `scripts/Enable-Lan.ps1` as Administrator with the current PC IP and the correct CIDR subnet. It updates its own forwarding entry and firewall rule.
4. From a second device, try the same URL in a browser. Disable guest/client isolation for the intended test LAN only if you control that router and want those devices to communicate.
5. If the browser works but the app does not, confirm the full `http://`/`https://` URL and app/server compatibility. Do not hide certificate validation errors. Plan trusted HTTPS before wider deployment.
6. If Windows changed the PC's LAN address, update `.env` (`SITE_URL`), restart, remove the old forwarding entry, and enable the new address. Router DHCP reservation prevents this.

Remove the project-specific LAN entry and firewall rule using an Administrator PowerShell:

```powershell
.\scripts\Disable-Lan.ps1 -LanAddress 192.168.1.20
```

Replace the example IP with the address originally configured. Never forward the database port or use a broad inbound allow rule as a troubleshooting shortcut.

## HTTPS after the pilot

Use a domain/subdomain with local DNS resolving to the local server, a reverse proxy that supports WebSockets and file sizes, and a certificate trusted by every client. DNS, certificate validity, and server time must keep working during an outage. A public certificate obtained with DNS validation can be installed before the outage; renewal must happen before expiry. Stock mobile apps do not reliably accept self-signed certificates. Private CAs require deliberate device trust setup and client testing.
