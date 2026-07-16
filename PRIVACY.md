# Hydra Privacy Policy

Effective date: July 16, 2026

Hydra is a macOS download manager with browser extensions for Chrome-compatible browsers and Firefox. Hydra is designed to process download information locally on the user's Mac. The developer does not operate a server that receives browsing or download data.

## Data Hydra processes

After the user explicitly enables local data transfer in the extension settings, Hydra may process the following information when a download is selected or matches the user's automatic-capture rules:

- download URL and referring page URL;
- suggested file name and file size;
- cookies associated with the download URL;
- browser User-Agent;
- download source and transfer status;
- extension settings, including domain and file-type rules.

This information is used only to transfer the selected download to the Hydra application and perform that download with the user's authenticated browser session.

## Where data goes

The browser extension sends download information to the Hydra application on the same Mac using the browser's native messaging interface. Hydra does not send this information to the developer, advertising networks, analytics providers, or other third parties.

The destination server selected by the user naturally receives the network request required to download the requested file. Its handling of that request is governed by the destination site's privacy policy.

## Local storage and retention

Extension settings and up to 20 recent transfer records are stored locally in the browser profile. The Hydra application stores download state and history locally on the Mac. Records remain until they are replaced, cleared by the user, the extension data is removed, or the application is uninstalled.

## User control

- Automatic capture is disabled until the user explicitly allows local data transfer and enables capture.
- The user can disable automatic capture, restrict it by site or file type, or remove the extension at any time.
- Download history can be cleared in Hydra.
- Removing the extension clears its locally stored data according to the browser's normal uninstall behavior.

## Security

Hydra uses the operating system and browser native messaging mechanisms for local communication. Sensitive session information is used only for the requested download and is not written to the extension transfer log.

## Chrome Web Store Limited Use

Hydra's use of information received from Chrome APIs complies with the Chrome Web Store User Data Policy, including the Limited Use requirements. Data is used only to provide the user-facing download functionality, is not used for advertising or profiling, is not sold or transferred to third parties, and is not accessed by humans except when the user explicitly provides diagnostic information for support.

## Children

Hydra is a general-purpose utility and does not knowingly collect personal information from children.

## Changes

Material changes to this policy or Hydra's data handling will be disclosed in the application, extension, repository, or store listing before the changed handling begins.

## Contact

Questions and privacy requests can be submitted through [Hydra GitHub Issues](https://github.com/pushipu/Hydra/issues).
