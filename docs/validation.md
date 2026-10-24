# Pilot verification — October 24, 2026

Verified on Windows 11 using a dedicated WSL 2 runtime and the images pinned in this repository. The host's WSL outbound internet connection was unavailable, so the initial runtime packages were downloaded through Windows from Ubuntu's repositories, with repository signatures and package hashes checked before installation. The service images were fetched by their pinned digests through Windows. The cached-image import script was exercised successfully.

## Passed on the local server

- HTTPS health with certificate verification and a locally served web client; old HTTP bookmarks redirect.
- Offline configuration, open anonymous signup, strong password rejection, ordinary user privileges, public BartaLAN membership, and a lobby message from the new user.
- Two independent account logins.
- Authenticated secure WebSocket delivery of Bengali text to another account.
- Direct messaging.
- PNG and binary upload/download by another account, with matching SHA-256 hashes.
- Rejection of unauthenticated attachment downloads.
- Account, message, image, and file persistence after stopping and starting the services.
- Actual application/database network isolation: one internal network each, no external default route, and no directly published ports.
- Gateway ingress through one published HTTPS port; the CA signing key is not mounted in the gateway.
- Certificate reuse and reissue after an IP change while preserving the CA; incomplete CA files fail safely.
- Rejection of an unknown CA, a wrong hostname and obsolete TLS versions; excessive signup attempts receive HTTP 429.
- Initial and repeated administrator bootstrap, with credentials preserved.
- Backup creation with the application quiesced, including TLS keys/certificates, followed by restart.
- PowerShell, Python, shell, Compose, and integration-test syntax/configuration checks.
- Windows forwarding on the LAN and loopback addresses. The original host port 8065 was inside a Windows-reserved range; the pilot now uses 18065, rejects reserved ports during setup, and verifies the forwarded endpoint before reporting LAN setup success.
- Before the HTTPS migration, the operator confirmed that the login page opened in a phone browser on the same Wi-Fi. Phone trust/HTTPS still needs a device check.

Local machine addresses, account passwords, chat data, and backup files are excluded from version control. The GitHub workflow independently starts a disposable stack and exercises messaging, attachments, isolation, persistence, and backup creation on future pushes.

## Still requires a real-device drill

The automated tests use HTTPS/secure WebSocket clients that trust the specific local CA. Native Android/Desktop app behavior with this CA, phone-browser trust setup, a complete chat/file exchange on physical devices, an actual router-WAN disconnection, ISP routing across homes, and a complete backup restoration are separate acceptance checks. The earlier phone-browser login page check confirms the Wi-Fi route to the server; it does not establish these remaining behaviors.
