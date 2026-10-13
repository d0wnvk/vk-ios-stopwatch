# Photo export

This feature lets the Mac download original photos and videos from the iPhone
over local Wi-Fi. The Mac initiates every connection; the iPhone does not need
to connect to a listening Mac receiver.

## Use it

1. Open **Stopwatch → Photos** on the iPhone.
2. Tap **Start sharing** and grant Full Photos and Local Network access.
3. Tap **Copy connection URL**.
4. On the Mac, run:

   ```bash
   python3 ~/Xcode/stopwatch/stopwatch/Features/PhotoExport/iphone-photo-export.py 2026-09-19
   ```

5. Paste the copied URL when prompted.

The date is the capture date. Downloads are written to:

```text
~/Downloads/260919-iphone-media/
```

Replace `2026-09-19` with the required date. Keep the Photos screen open until
the Mac reports completion. Sharing stops when the screen closes, **Stop sharing**
is tapped, or the app enters the background.

## Mac script options

```text
--dry-run                         List matching files without downloading
--timezone Asia/Ho_Chi_Minh       Interpret the date in another timezone
--destination /path/to/folder     Override the default Downloads folder
--iphone 'http://IP:PORT/#KEY'    Supply the URL without an interactive prompt
```

The session key changes every time sharing starts. Quote a URL containing `#` in
the shell.

## What is transferred

The feature exports original PhotoKit resources, including photos, videos,
alternate photos, burst resources, and paired Live Photo videos. The Photos
library is not modified. Edited renderings and edit histories are not exported.
An iCloud-only original may need to download on the iPhone first. Locked Hidden,
Recently Deleted, or otherwise inaccessible assets may be skipped.

The Mac verifies the byte count and SHA-256 checksum before publishing each file.
Files use the original iPhone filename plus duration, such as
`IMG_5979-00-12.MOV`. Photos use `00-00`; video durations are rounded to the
nearest second and formatted as `MM-SS`. Existing files are never overwritten:
identical files are reused, while a different file with the same name receives a
numeric suffix such as `IMG_5979-00-12 (2).MOV`. Each run writes a JSON manifest
containing file names, durations, checksums, and completion status.

## Source files

- `PhotoExportView.swift` — SwiftUI screen and Copy URL button.
- `PhotoExportServer.swift` — Photos query, iPhone Wi-Fi listener, and resource streaming.
- `PhotoExportHTTP.swift` — bounded HTTP request parsing and response streaming.
- `PhotoExportInfo.plist` — Photos and Local Network permission descriptions are configured at the app target level.

Both devices must be on the same trusted Wi-Fi. Transfers use local HTTP with a
random session key and are not encrypted. A VPN, guest-network client isolation,
local-network permissions, or endpoint security software can block the connection.
