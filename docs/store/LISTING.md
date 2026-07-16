# Hydra browser extension store listing

## Common metadata

- **Name:** Hydra Download Manager
- **Category:** Productivity
- **Homepage:** https://github.com/pushipu/Hydra
- **Support:** https://github.com/pushipu/Hydra/issues
- **Privacy policy:** https://github.com/pushipu/Hydra/blob/main/PRIVACY.md

### Short description

Send browser downloads to Hydra for fast, controllable downloading on your Mac.

### Full description

Hydra connects your browser to the Hydra download manager for macOS.

Use automatic capture or “Download with Hydra” from the context menu to hand a download to the native app. Hydra can reuse the browser session for authenticated files while the application provides pause and resume controls, segmented progress, speed statistics, history, notifications, and download management.

The extension stays focused:

- automatic or manual download capture;
- site, file-type, minimum-size, and connection rules;
- connection status and a short local transfer log;
- quick access to Hydra and extension settings.

Hydra requires the free Hydra macOS application. Browser data is transferred only to Hydra on the same Mac and is not sent to the developer or advertising services.

## Chrome Web Store permission justifications

- **downloads:** detect, cancel, and hand selected browser downloads to Hydra.
- **contextMenus:** provide “Download with Hydra” for links and media.
- **cookies:** reuse the user's authenticated session for the selected download.
- **nativeMessaging:** communicate with the locally installed Hydra application.
- **storage:** keep extension settings and a bounded local transfer log.
- **host access to all URLs:** support downloads from any site selected by the user. Access is used only for download handling.

## Data-use declarations

- Website content: download URL, referrer, response-derived file information, and cookies for the selected download.
- Web browsing activity: only URLs involved in downloads selected by the user or matching enabled capture rules.
- Authentication information: cookies are passed locally to Hydra only to perform the requested authenticated download.
- No analytics, advertising, profiling, sale of data, or developer-operated data server.

## Reviewer notes

Hydra is a companion extension for the notarized macOS application available from GitHub Releases. Install and launch Hydra once before testing native messaging. Automatic capture is disabled until the user accepts the local-data disclosure in extension settings.

Test flow:

1. Install and launch Hydra from https://github.com/pushipu/Hydra/releases/latest.
2. Install the browser extension.
3. Open extension settings, accept local data transfer, and enable automatic capture.
4. Download an HTTP or HTTPS file, or choose “Download with Hydra” from a link's context menu.
5. Confirm that the transfer appears in the extension popup and Hydra.
