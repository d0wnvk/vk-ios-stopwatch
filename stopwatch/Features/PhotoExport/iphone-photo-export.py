#!/usr/bin/env python3
"""Download a capture day's originals FROM Stopwatch on iPhone TO this Mac."""
import argparse
import datetime as dt
import hashlib
import http.client
import json
import os
from pathlib import Path
import re
import secrets
import sys
import time
from urllib.error import HTTPError, URLError
from urllib.parse import urlencode, urlsplit
from urllib.request import Request, build_opener, ProxyHandler, HTTPRedirectHandler
from zoneinfo import ZoneInfo


class NoRedirect(HTTPRedirectHandler):
    def redirect_request(self, *args, **kwargs):
        return None


def local_zone():
    path = os.path.realpath('/etc/localtime')
    return path.split('/zoneinfo/')[-1] if '/zoneinfo/' in path else 'UTC'


def parse_connection(value):
    url = urlsplit(value.strip())
    if (url.scheme != 'http' or not url.hostname or url.username or url.password
            or not re.fullmatch(r'[A-Za-z0-9_-]{20,128}', url.fragment)
            or url.path not in ('', '/') or url.query):
        raise ValueError('Paste the full http://IP:PORT/#SESSION_KEY URL shown on iPhone.')
    _ = url.port  # validates malformed ports
    return f'http://{url.netloc}', url.fragment


def checksum(path):
    digest = hashlib.sha256()
    with path.open('rb') as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b''):
            digest.update(chunk)
    return digest.hexdigest()


def export_name(name, duration):
    source = Path(name)
    if not re.fullmatch(r'\d{2,}-[0-5]\d', duration):
        raise ValueError('Invalid duration from iPhone.')
    return f'{source.stem}-{duration}{source.suffix}'


def available_target(folder, name, duration, expected):
    """Return original name plus duration, adding a suffix only on collision."""
    name = export_name(name, duration)
    source = Path(name)
    stem, suffix = source.stem, source.suffix
    for number in range(1, 10000):
        candidate_name = name if number == 1 else f'{stem} ({number}){suffix}'
        candidate = folder / candidate_name
        if not candidate.exists():
            return candidate
        if candidate.is_file() and not candidate.is_symlink() and checksum(candidate) == expected:
            return candidate
    raise ValueError(f'Too many files named {name!r} in the destination folder.')


class Client:
    def __init__(self, connection, timeout=3600):
        self.base, self.token = parse_connection(connection)
        # Local connections must not go through an HTTP proxy.
        self.opener = build_opener(ProxyHandler({}), NoRedirect())
        self.timeout = timeout

    def open(self, path):
        request = Request(self.base + path, headers={'Authorization': 'Bearer ' + self.token})
        return self.opener.open(request, timeout=self.timeout)

    def manifest(self, day, timezone):
        with self.open('/manifest?' + urlencode({'date': day, 'timezone': timezone})) as response:
            value = json.load(response)
        if not isinstance(value, dict) or value.get('date') != day or value.get('timezone') != timezone:
            raise ValueError('iPhone returned an unexpected date/timezone.')
        if not isinstance(value.get('files'), list):
            raise ValueError('Invalid file manifest.')
        ids = set()
        for entry in value['files']:
            validate_entry(entry)
            if entry['id'] in ids:
                raise ValueError('Duplicate file ID in manifest.')
            ids.add(entry['id'])
        return value

    def download(self, entry, folder):
        validate_entry(entry)
        partial = folder / ('.' + secrets.token_hex(16) + '.part')
        try:
            with self.open('/file/' + entry['id']) as response:
                expected = response.headers.get('X-SHA256', '')
                if not re.fullmatch(r'[a-f0-9]{64}', expected):
                    raise ValueError('Missing or invalid checksum from iPhone.')
                size = int(response.headers.get('Content-Length', '-1'))
                if size < 0:
                    raise ValueError('Missing file length from iPhone.')
                digest = hashlib.sha256()
                received = 0
                with partial.open('xb') as stream:
                    while True:
                        data = response.read(1024 * 1024)
                        if not data:
                            break
                        received += len(data)
                        if received > size:
                            raise ValueError('Downloaded more bytes than advertised.')
                        stream.write(data)
                        digest.update(data)
                    stream.flush()
                    os.fsync(stream.fileno())
            if received != size or digest.hexdigest() != expected:
                raise ValueError('Incomplete or damaged download; checksum/length verification failed.')
            target = available_target(folder, entry['name'], entry['duration'], expected)
            try:
                os.link(partial, target)  # atomic and never overwrites
            except FileExistsError:
                if target.is_symlink() or checksum(target) != expected:
                    raise ValueError(f'Existing file differs and was preserved: {target.name}')
            return {**entry, 'filename': target.name, 'bytes': size, 'sha256': expected, 'status': 'verified'}
        finally:
            partial.unlink(missing_ok=True)


def validate_entry(entry):
    if not isinstance(entry, dict) or not re.fullmatch(r'[a-f0-9]{64}-[0-9]{1,5}', str(entry.get('id', ''))):
        raise ValueError('Invalid file ID from iPhone.')
    name = entry.get('name')
    duration = entry.get('duration')
    if not isinstance(duration, str) or not re.fullmatch(r'\d{2,}-[0-5]\d', duration):
        raise ValueError('Invalid duration from iPhone.')
    if (not isinstance(name, str) or not name or name in ('.', '..')
            or '/' in name or '\\' in name or len(name.encode()) > 170
            or any(ord(c) < 32 for c in name)):
        raise ValueError('Invalid filename from iPhone.')


def error_message(error):
    if isinstance(error, HTTPError):
        if error.code == 401:
            return 'Session key expired or incorrect. Copy the current URL from Stopwatch → Photos.'
        try:
            detail = json.loads(error.read(16384)).get('error', '')
        except (ValueError, OSError):
            detail = ''
        return f'iPhone HTTP {error.code}: {detail}'
    if isinstance(error, (URLError, ConnectionError, TimeoutError)):
        return f'{error}. Keep Stopwatch → Photos sharing open, allow Local Network access, and check both devices are on the same Wi-Fi.'
    return str(error)


def save_report(path, report):
    temporary = path.with_suffix('.json.tmp')
    temporary.write_text(json.dumps(report, indent=2), encoding='utf-8')
    temporary.replace(path)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('date', help='Capture day: YYYY-MM-DD')
    parser.add_argument('--iphone', help='Quoted connection URL shown by Stopwatch; otherwise prompted')
    parser.add_argument('--destination', type=Path, help='Override ~/Downloads/YYYY-MM-DD-all-iphone-media')
    parser.add_argument('--timezone', default=local_zone(), help='IANA capture-day timezone; default: Mac timezone')
    parser.add_argument('--dry-run', action='store_true', help='List matching media without downloading')
    args = parser.parse_args()
    try:
        if dt.date.fromisoformat(args.date).isoformat() != args.date:
            raise ValueError('Use YYYY-MM-DD')
        ZoneInfo(args.timezone)
        connection = args.iphone or input('Paste connection URL from Stopwatch → Photos: ').strip()
        client = Client(connection)
    except (ValueError, KeyError, EOFError) as error:
        parser.error(str(error))
    print(f'Connecting to iPhone for {args.date} ({args.timezone})…', flush=True)
    try:
        manifest = client.manifest(args.date, args.timezone)
    except (OSError, ValueError, http.client.HTTPException) as error:
        print('Connection failed: ' + error_message(error), file=sys.stderr)
        return 1
    files = manifest['files']
    print(f"Found {manifest.get('assets', '?')} photos/videos; {len(files)} original files.", flush=True)
    unavailable = manifest.get('unavailableAssets', 0)
    if unavailable:
        print(f'Warning: {unavailable} assets have no accessible originals.', flush=True)
    if args.dry_run:
        for entry in files:
            print(entry['name'])
        return 2 if unavailable else 0
    folder = (args.destination or (Path.home() / 'Downloads' / (args.date + '-all-iphone-media'))).expanduser().resolve()
    folder.mkdir(parents=True, exist_ok=True)
    report_path = folder / ('manifest-' + secrets.token_hex(8) + '.json')
    report = {'date': args.date, 'timezone': args.timezone, 'complete': False,
              'expectedFiles': len(files), 'unavailableAssets': unavailable, 'files': []}
    save_report(report_path, report)
    print(f'Destination: {folder}', flush=True)
    interrupted = False
    try:
        for index, entry in enumerate(files, 1):
            print(f"[{index}/{len(files)}] {entry['name']}", flush=True)
            for attempt in range(3):
                try:
                    result = client.download(entry, folder)
                    break
                except (OSError, ValueError, http.client.HTTPException) as error:
                    message = error_message(error)
                    retryable = not isinstance(error, ValueError) and (not isinstance(error, HTTPError) or error.code in (409, 500, 503))
                    if attempt == 2 or not retryable:
                        result = {**entry, 'status': 'failed', 'error': message}
                        print('  FAILED: ' + message, flush=True)
                        break
                    print(f'  Retrying interrupted request ({attempt + 1}/2)…', flush=True)
                    time.sleep(2)
            report['files'].append(result)
            save_report(report_path, report)
    except KeyboardInterrupt:
        interrupted = True
        print('\nCancelled. Verified files were preserved.', flush=True)
    verified = sum(item['status'] == 'verified' for item in report['files'])
    report['complete'] = not interrupted and not unavailable and verified == len(files)
    save_report(report_path, report)
    print(f"{'COMPLETE' if report['complete'] else 'INCOMPLETE'}: {verified}/{len(files)} files verified.\nReport: {report_path}", flush=True)
    return 0 if report['complete'] else 2


if __name__ == '__main__':
    try:
        sys.exit(main())
    except KeyboardInterrupt:
        sys.exit(130)
