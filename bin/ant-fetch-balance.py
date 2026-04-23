#!/usr/bin/env python3
"""
bin/ant-fetch-balance.py — Automated Anthropic balance fetch using Chrome session cookies.

Reads platform.claude.com session cookies from Chrome's cookie database,
decrypts them using the macOS Keychain key, and calls the console API
to get the current credit balance and usage data.

Fully headless, no screen control, no manual work.
Cookies persist ~30 days; Chrome refreshes them automatically when used.

Usage:
    python3 bin/ant-fetch-balance.py
    python3 bin/ant-fetch-balance.py --org-id 6fa1a636-f063-4651-aef2-f7ebaa25c49d

Output:
    JSON with balance, invoices, and available usage data
"""

import os, sys, json, sqlite3, shutil, tempfile, subprocess
from datetime import datetime, timezone
import urllib.request, urllib.error

ORG_ID = "6fa1a636-f063-4651-aef2-f7ebaa25c49d"
PLATFORM_HOST = "platform.claude.com"
CHROME_COOKIES = os.path.expanduser("~/Library/Application Support/Google/Chrome/Default/Cookies")

def get_chrome_encryption_key():
    """Get the Chrome cookie encryption key from macOS Keychain."""
    try:
        result = subprocess.run(
            ["security", "find-generic-password", "-w", "-s", "Chrome Safe Storage", "-a", "Chrome"],
            capture_output=True, text=True, timeout=10
        )
        if result.returncode == 0:
            password = result.stdout.strip()
            import hashlib
            # Chrome uses PBKDF2 with the keychain password to derive the AES key
            key = hashlib.pbkdf2_hmac('sha1', password.encode('utf8'), b'saltysalt', 1003, dklen=16)
            return key
    except Exception as e:
        print(f"[ant-fetch] Keychain error: {e}", file=sys.stderr)
    return None

def decrypt_cookie(encrypted_value, key):
    """Decrypt a Chrome cookie value (v10 AES-CBC format)."""
    if not encrypted_value or not encrypted_value.startswith(b'v10'):
        # Not encrypted or old format
        return encrypted_value.decode('utf-8', errors='replace') if encrypted_value else ''
    try:
        from Crypto.Cipher import AES
        iv = b' ' * 16
        encrypted = encrypted_value[3:]  # Strip 'v10' prefix
        cipher = AES.new(key, AES.MODE_CBC, IV=iv)
        decrypted = cipher.decrypt(encrypted)
        # Remove PKCS7 padding
        pad_size = decrypted[-1]
        return decrypted[:-pad_size].decode('utf-8', errors='replace')
    except ImportError:
        # pycryptodome not available — try without decryption for non-encrypted cookies
        return ''
    except Exception as e:
        return ''

def get_platform_cookies():
    """Extract platform.claude.com cookies from Chrome's SQLite database."""
    if not os.path.exists(CHROME_COOKIES):
        print(f"[ant-fetch] Chrome cookies not found at {CHROME_COOKIES}", file=sys.stderr)
        return {}
    
    # Copy to temp file (Chrome may have it locked)
    with tempfile.NamedTemporaryFile(suffix='.db', delete=False) as tmp:
        tmp_path = tmp.name
    shutil.copy2(CHROME_COOKIES, tmp_path)
    
    try:
        conn = sqlite3.connect(tmp_path)
        cursor = conn.cursor()
        cursor.execute(
            "SELECT name, encrypted_value, value FROM cookies WHERE host_key LIKE ?",
            (f'%{PLATFORM_HOST}%',)
        )
        rows = cursor.fetchall()
        conn.close()
    finally:
        os.unlink(tmp_path)
    
    if not rows:
        print(f"[ant-fetch] No cookies found for {PLATFORM_HOST}", file=sys.stderr)
        return {}
    
    key = get_chrome_encryption_key()
    cookies = {}
    for name, encrypted_value, plain_value in rows:
        if encrypted_value:
            value = decrypt_cookie(encrypted_value, key) if key else plain_value
        else:
            value = plain_value
        if value:
            cookies[name] = value
    
    return cookies

def call_console_api(endpoint, cookies):
    """Call a platform.claude.com API endpoint using session cookies."""
    cookie_header = '; '.join(f'{k}={v}' for k, v in cookies.items() if v)
    headers = {
        'Cookie': cookie_header,
        'Accept': 'application/json',
        'User-Agent': 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36',
    }
    url = f"https://{PLATFORM_HOST}{endpoint}"
    try:
        req = urllib.request.Request(url, headers=headers)
        with urllib.request.urlopen(req, timeout=15) as resp:
            return json.loads(resp.read().decode()), resp.status
    except urllib.error.HTTPError as e:
        body = e.read().decode()[:300]
        return json.loads(body) if body.startswith('{') else {'error': body}, e.code
    except Exception as e:
        return {'error': str(e)}, 0

def main():
    org_id = ORG_ID
    for arg in sys.argv[1:]:
        if arg.startswith('--org-id='):
            org_id = arg.split('=', 1)[1]
    
    print(f"[ant-fetch] Extracting Chrome cookies for {PLATFORM_HOST}...", file=sys.stderr)
    cookies = get_platform_cookies()
    
    if not cookies:
        print(json.dumps({"error": "no_cookies", "message": "Chrome cookies not found or empty"}))
        sys.exit(1)
    
    print(f"[ant-fetch] Found {len(cookies)} cookies", file=sys.stderr)
    
    result = {"fetched_at": datetime.now(timezone.utc).isoformat(), "org_id": org_id}
    
    # Fetch invoices (known working endpoint)
    data, status = call_console_api(f"/api/organizations/{org_id}/invoices/overdue", cookies)
    result["invoices_overdue"] = data
    print(f"[ant-fetch] invoices/overdue: HTTP {status}", file=sys.stderr)
    
    # Try billing endpoint (subscription via POST-based flow)
    for endpoint in [
        f"/api/organizations/{org_id}/subscription",
        f"/api/organizations/{org_id}/account",
        f"/api/console/organizations/{org_id}/billing",
        f"/api/console/organizations/{org_id}",
    ]:
        data, status = call_console_api(endpoint, cookies)
        name = endpoint.split('/')[-1]
        result[name] = {"status": status, "data": data}
        print(f"[ant-fetch] {name}: HTTP {status} — {str(data)[:100]}", file=sys.stderr)
    
    print(json.dumps(result, indent=2))

if __name__ == '__main__':
    main()
