# Download iPhone photos over Wi-Fi

1. On iPhone open **Stopwatch → Photos → Start sharing**. Grant Full Photos
   access and Local Network access if requested. Keep the screen open.
2. Tap **Copy connection URL** beneath the generated URL.
3. On Mac run:

   ```bash
   python3 ~/Xcode/iphone-photo-export.py 2026-09-19
   ```

4. Paste the connection URL when prompted. Universal Clipboard can transfer
   the copied URL between devices when configured; otherwise use Share or copy
   the address manually.

Files go into `~/Downloads/260919-iphone-media/`. Exported media keeps
the original name and adds its duration, for example `IMG_5979-00-12.MOV`.
The Mac initiates every
connection. It does not open a listening port or require an inbound firewall rule.
Stop the old receiver with Ctrl-C before using this replacement script.

Options: `--dry-run` lists files; `--timezone Asia/Ho_Chi_Minh` selects a day in
that timezone (default: Mac timezone); `--destination /path` overrides the output
directory. `--iphone 'http://IP:PORT/#KEY'` supplies the URL without prompting.
Quote URLs containing `#`. The URL/session key changes whenever sharing restarts.

Downloads preserve original photo/video resources, alternate photos, and paired
Live Photo videos. Burst assets exposed by PhotoKit are included. Edited renderings
and edit histories are not exported. iCloud-only originals may be downloaded by
the iPhone before serving them. Locked Hidden / Recently Deleted items and assets
without accessible resources cannot be guaranteed. Full Photos permission is required.

Each original is prepared in a temporary file on iPhone and streamed in bounded
chunks; free space must accommodate the largest original. Mac verifies SHA-256
and file length before publishing the file. Files use their original iPhone
filename; a numeric suffix is added only when a different file already uses that
name. Existing files are never overwritten: matching files are verified and
reused; conflicts are reported. Rerunning can redownload files to
verify them. Per-run manifest JSON records checksums and complete/incomplete status.
Partial downloads are removed on handled failures or cancellation. Force-killing
the process may leave hidden `.part` files. Embedded capture metadata is preserved;
Finder creation dates reflect download time.

Keep both devices on the same trusted Wi-Fi. HTTP transfers use a random session
key but are not encrypted. Sharing stops when the Photos screen closes, Stop is
tapped, or the app enters the background. Wi-Fi isolation, VPNs, local-network
permissions, and endpoint filters may still block outgoing Mac connections.
