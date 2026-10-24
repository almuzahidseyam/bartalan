# Network topology and troubleshooting

The initial target is one trusted LAN. A router's Wi-Fi icon means a device has connected to that router, not that it can reach another household's router.

| Scope | Required path | Who controls it |
| --- | --- | --- |
| Same LAN | Client → LAN router/switch → server PC | LAN operator |
| Several homes on one ISP | Client → ISP access network → locally reachable server | ISP plus server operator |
| Different ISPs | Access networks plus working inter-ISP local routing | Participating ISPs |

Different Wi-Fi networks can work when the networks route to the server. The supplied Windows firewall currently accepts only the chosen private LAN subnet; it does not grant access to other ISP subscribers. A private address such as 192.168.1.2 is meaningful only inside its own network. Another household may use exactly the same address for an unrelated device.

While the internet is working, cross-ISP service can be designed with a reachable public endpoint and suitable firewall/NAT or a VPN. CGNAT may require an ISP change or an ISP-hosted server. During an internet shutdown, the service survives across homes/ISPs only if the required ISP local routing/interconnection also survives. A domain or HTTPS certificate does not create that routing. For a community deployment, arrange an always-on server inside the participating ISP/local network with the operators, then test from actual subscribers during an uplink-disconnection drill.

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
5. If the browser works but the app does not, confirm the full `https://` URL, local CA trust, and app/server compatibility. Do not hide certificate validation errors. A stock app may reject a user-installed CA; see [HTTPS setup](https.md).
6. If Windows changed the PC's LAN address, update `.env` (`SITE_URL`), restart, remove the old forwarding entry, and enable the new address. Router DHCP reservation prevents this.

Remove the project-specific LAN entry and firewall rule using an Administrator PowerShell:

```powershell
.\scripts\Disable-Lan.ps1 -LanAddress 192.168.1.20
```

Replace the example IP with the address originally configured. Never forward the database port or use a broad inbound allow rule as a troubleshooting shortcut.

## HTTPS and offline name resolution

The pilot now uses a private local CA and an HTTPS reverse proxy supporting WebSockets/files. Install the public CA on each client and confirm the exact server URL validates. DNS, certificate validity and server time must keep working during an outage. With a future domain, use local DNS resolving to the local server and obtain a publicly trusted certificate beforehand with DNS validation; renewal must happen before expiry. Private CAs still require device trust setup and actual native-app testing. See [HTTPS setup](https.md).
