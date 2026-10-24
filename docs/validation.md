# Pilot verification — October 24, 2026

Verified on Windows 11 using a dedicated WSL 2 runtime and the images pinned in this repository. The host's WSL outbound internet connection was unavailable, so the initial runtime packages were downloaded through Windows from Ubuntu's repositories, with repository signatures and package hashes checked before installation. The service images were fetched by their pinned digests through Windows. The cached-image import script was exercised successfully.

## Passed on the local server

- HTTP health and locally served web client.
- Offline configuration and rejection of uninvited registration.
- Two independent account logins.
- Authenticated WebSocket delivery of Bengali text to another account.
- Direct messaging.
- PNG and binary upload/download by another account, with matching SHA-256 hashes.
- Rejection of unauthenticated attachment downloads.
- Account, message, image, and file persistence after stopping and starting the services.
- Actual application/database network isolation: one internal network each, no external default route, and no directly published ports.
- Gateway ingress through one published HTTP port.
- Initial and repeated administrator bootstrap, with credentials preserved.
- Backup creation with the application quiesced, followed by restart.
- PowerShell, Python, shell, Compose, and integration-test syntax/configuration checks.
- Windows forwarding on the LAN and loopback addresses, with a successful HTTP health response. The original host port 8065 was inside a Windows-reserved range; the pilot now uses 18065, rejects reserved ports during setup, and verifies the forwarded endpoint before reporting LAN setup success.
- The operator confirmed that the Mattermost login page opens in a phone browser on the same Wi-Fi after the forwarding fix.

Local machine addresses, account passwords, chat data, and backup files are excluded from version control. The GitHub workflow independently starts a disposable stack and exercises messaging, attachments, isolation, persistence, and backup creation on future pushes.

## Still requires a real-device drill

The automated tests use HTTP/WebSocket clients. Native Android/Desktop app behavior, a complete chat/file exchange on physical devices, an actual router-WAN disconnection, ISP routing across homes, and a complete backup restoration are separate acceptance checks. The phone-browser login page check confirms the Wi-Fi route to the server; it does not establish these remaining behaviors.
