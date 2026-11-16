#!/usr/bin/env python3
"""Synthetic process E2E. Run only inside the isolated local CI account."""
import hashlib
import json
import os
from pathlib import Path
import pwd
import socket
import sqlite3
import subprocess
import sys
import tempfile
import time

cli = Path(sys.argv[1]).resolve()
if sys.platform == 'darwin':
    raise SystemExit('Use rust-e2e-isolated.py; never replace the real user policy/socket')
home = Path(pwd.getpwuid(os.getuid()).pw_dir)
private = home / 'Library/Application Support/GreenBubbles'
private.mkdir(parents=True, exist_ok=True, mode=0o700)
policy = private / 'ai-read-policy.json'
sock = private / 'query.sock'
original = policy.read_bytes() if policy.exists() else None
checks = {}

def check(name, ok):
    checks[name] = bool(ok)
    if not ok:
        raise AssertionError(name)

def deny(ids):
    policy.write_text(json.dumps({'version': 1, 'conversationIds': ids}))
    policy.chmod(0o600)

def run(*args, input=None):
    return subprocess.run([str(cli), *args], input=input, capture_output=True, timeout=75)

server = None
try:
    with tempfile.TemporaryDirectory() as folder:
        root = Path(folder)
        ids = ['wxid_allowed', 'wxid_denied']
        for part in ['session', 'contact', 'message']:
            (root / part).mkdir()
        with sqlite3.connect(root / 'session/session.db') as db:
            db.execute('CREATE TABLE SessionTable(username TEXT, sort_timestamp INTEGER, summary TEXT)')
            db.executemany('INSERT INTO SessionTable VALUES (?, ?, ?)', [(i, 100-n, 'hello '+i) for n,i in enumerate(ids)])
        with sqlite3.connect(root / 'contact/contact.db') as db:
            db.execute('CREATE TABLE contact(username TEXT PRIMARY KEY, alias TEXT, remark TEXT, nick_name TEXT)')
            db.executemany('INSERT INTO contact VALUES (?, ?, ?, ?)', [(i,'',i,'') for i in ids])
        with sqlite3.connect(root / 'message/message_0.db') as db:
            db.execute('CREATE TABLE Name2Id(user_name TEXT)')
            db.execute("INSERT INTO Name2Id VALUES ('wxid_sender')")
            for identifier in ids:
                table = 'Msg_' + hashlib.md5(identifier.encode()).hexdigest()
                db.execute(f'CREATE TABLE [{table}](server_id INTEGER, sort_seq INTEGER, local_type INTEGER, real_sender_id INTEGER, create_time INTEGER, status INTEGER, message_content BLOB, packed_info_data BLOB, WCDB_CT_message_content INTEGER, compress_content BLOB)')
                for n in range(3):
                    db.execute(f'INSERT INTO [{table}] VALUES (?, ?, 1, 1, ?, 0, ?, NULL, 0, NULL)', (n+1,n+1,1700000000+n,'hello '+identifier))
        before = {str(p.relative_to(root)): hashlib.sha256(p.read_bytes()).hexdigest() for p in root.rglob('*') if p.is_file()}
        deny([])
        server = subprocess.Popen([str(cli),'query-serve',str(root),str(sock),'--decrypted'], stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)
        for _ in range(100):
            if sock.exists(): break
            if server.poll() is not None: raise AssertionError('server startup')
            time.sleep(.05)
        check('private-socket', sock.stat().st_mode & 0o777 == 0o600)
        status = run('source','status')
        check('app-source-without-client-config', status.returncode == 0 and json.loads(status.stdout)['ok'])
        first = run('chats','--limit','1')
        value = json.loads(first.stdout)
        check('list', first.returncode == 0 and len(value['items']) == 1)
        second = run('chats','--limit','1','--cursor',value['page']['nextCursor'])
        check('pagination', json.loads(second.stdout)['items'][0]['id'] != value['items'][0]['id'])
        found = run('chats','find','wxid_allowed')
        check('find', found.returncode == 0 and b'wxid_allowed' in found.stdout)
        contacts = run('contacts','list','--limit','1')
        check('contacts', contacts.returncode == 0)
        check('contacts-short-form', run('contacts','--limit','1').returncode == 0)
        check('source-short-form', run('source').returncode == 0)
        messages = run('messages','list','--conversation',ids[0],'--limit','1','--json')
        value = json.loads(messages.stdout)
        check('messages', messages.returncode == 0 and len(value['items']) == 1)
        exact = run('message','get','--conversation',ids[0],'--message',value['items'][0]['id'])
        check('exact-message', exact.returncode == 0 and b'hello' in exact.stdout)
        search = run('messages','search','--conversation',ids[0],'--query-stdin','--json',input=b'hello')
        check('stdin-search', search.returncode == 0 and len(json.loads(search.stdout)['items']) > 0)
        deny([ids[1]])
        hidden = run('chats')
        check('live-blacklist-list', hidden.returncode == 0 and ids[1].encode() not in hidden.stdout)
        denied = run('messages','list','--conversation',ids[1],'--json')
        check('live-blacklist-exact', denied.returncode != 0 and b'aiReadDenied' in denied.stdout and b'hello' not in denied.stdout)
        policy.write_text('{broken')
        check('corrupt-policy-closed', run('chats').returncode != 0)
        deny([])
        policy.chmod(0o644)
        check('unsafe-policy-closed', run('chats').returncode != 0)
        policy.chmod(0o600)
        def request(arguments):
            with socket.socket(socket.AF_UNIX) as client:
                client.settimeout(10)
                client.connect(str(sock))
                client.sendall(json.dumps({'arguments':arguments,'input':''}).encode())
                client.shutdown(socket.SHUT_WR)
                result = b''
                while chunk := client.recv(65536): result += chunk
                return json.loads(result)
        check('reject-empty-request', request([])['status'] != 0)
        for args in [['source','status','--profile','evil'], ['chats','list',str(root),'--decrypted'], ['help'], ['source','presentation']]:
            check('reject-'+'-'.join(args[:2]), request(args)['status'] != 0)
        with socket.socket(socket.AF_UNIX) as client:
            client.connect(str(sock))
            client.sendall(b'{invalid')
        check('malformed-client-survival', run('source','status').returncode == 0)
        after = {str(p.relative_to(root)): hashlib.sha256(p.read_bytes()).hexdigest() for p in root.rglob('*') if p.is_file()}
        check('source-unchanged', before == after)
        server.terminate()
        server.wait(timeout=10)
        check('unavailable-no-fallback', run('source','status').returncode != 0)
        # Restart reclaims only the old private socket.
        server = subprocess.Popen([str(cli),'query-serve',str(root),str(sock),'--decrypted'], stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)
        for _ in range(100):
            if run('source','status').returncode == 0: break
            time.sleep(.05)
        check('restart-reconnect', run('source','status').returncode == 0)
finally:
    if server is not None and server.poll() is None:
        server.terminate()
        server.wait(timeout=10)
    if sock.exists(): sock.unlink()
    if original is None:
        policy.unlink(missing_ok=True)
    else:
        policy.write_bytes(original)
        policy.chmod(0o600)
print(json.dumps({'passed': all(checks.values()), 'checks': checks}, indent=2))
