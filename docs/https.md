# Local HTTPS and client trust

The default deployment serves HTTPS on port 18065. `scripts/Start.ps1` creates a local root CA and a one-year server certificate with SAN entries for the configured `SITE_URL` hostname/IP, localhost and 127.0.0.1. OpenSSL verifies the signing chain, key pairs, validity and names before reuse. It renews the leaf certificate when fewer than 30 days remain or the address changes, preserving the CA so client trust stays valid. Run Start periodically to perform this check; there is no unattended renewal job. A near-expiry CA requires planned replacement and client trust updates.

The gateway accepts TLS 1.2/1.3 and exposes no HTTP application port. Old HTTP bookmarks on the same port receive a redirect. Always share the HTTPS URL directly: a redirect cannot encrypt information already sent over HTTP. HTTP health checks exist only on a container-loopback listener. Mattermost-to-database traffic stays inside the local internal Docker network; this does not encrypt storage or protect a compromised host.

## Install trust

Only distribute `certificates/BartaLAN-Root-CA.cer` (DER) or `.crt` (PEM). Compare its SHA-256 fingerprint with `certificates/fingerprint.txt` on the administrator's PC using a trusted transfer, such as USB. Installing a root CA grants trust to certificates signed by its key. Install only this known certificate on intended devices; keep `.secrets/tls/ca.key` private. The gateway receives only `.secrets/tls/server`, without the CA signing key.

- **Server Windows account:** run `scripts/Trust-LocalCertificate.ps1`. It imports this CA into the current user's Trusted Root store. It does not modify machine-wide trust.
- **Other Windows PCs:** transfer the public `.cer`, open it, choose Install Certificate → Current User → Place all certificates in the following store → Trusted Root Certification Authorities. Restart the browser/app if needed.
- **Android:** transfer the public `.crt`/`.cer`. In Settings search for Install a certificate, choose **CA certificate**, and select the file. Menu names and restrictions vary by Android version/device management. A screen lock and confirmation may be required. Install it as a CA, rather than a Wi-Fi-only certificate. Then open the exact HTTPS address in the browser and confirm there is no certificate warning.

Stock Mattermost Android may refuse user-installed CAs. Browser success does not establish native-app support. Do not disable certificate verification or use warning bypasses. The supported pilot path must be confirmed on the intended browser/device; native apps need their own acceptance test. [Mattermost mobile troubleshooting](https://docs.mattermost.com/deployment-guide/mobile/mobile-troubleshooting) recommends publicly trusted certificates.

To remove Windows trust later, open the current user's certificate manager and delete the matching **BartaLAN Local Root CA** from Trusted Root Certification Authorities. Verify its fingerprint first. Remove it on client devices when retiring this server or after CA-key compromise. Do not delete/recreate the CA as a routine troubleshooting step.

## A future domain

Owning a .com domain does not make a private LAN IP reachable from another ISP. With a domain under your control, obtain a publicly trusted certificate using DNS validation, install it in the proxy and configure local DNS to resolve the name to the reachable server. Public certificate renewal needs online access to the issuer/DNS provider. Local DNS and the network path must keep working during outages. The current private CA script does not provision public certificates automatically.

## Security limits and administration

Signup is open to anyone who can reach the server. Email verification/delivery are disabled for offline operation, so an email is not proof of identity. Keep the LAN firewall restriction; review accounts, remove abusive users, moderate public channels and use private channels for restricted groups. Ordinary signup never grants administrator privileges. Users retain the edition's default team/channel creation permissions; monitor those as well.

Passwords require 12+ characters with upper/lowercase, numbers and symbols. The proxy throttles signup POSTs to 5/minute with a burst of 20 and login POSTs to 20/minute with a burst of 40 per apparent source IP. Windows forwarding may group the LAN behind one source address. These limits reduce bursts; they are not complete abuse prevention or storage quotas. Monitor disk usage and backups. Uploaded files are not automatically virus scanned.

HTTPS protects traffic between a trusted client and the gateway. Mattermost is not end-to-end encrypted; a server administrator can access stored messages/files. Disk/backup encryption is a separate task. Keep Windows, WSL and the pinned images updated deliberately while internet access is available, protect the administrator password and CA key, and maintain an off-PC backup.
