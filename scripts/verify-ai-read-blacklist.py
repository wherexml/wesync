#!/usr/bin/env python3
"""Repeatable CLI E2E using only synthetic SQLite data; restore policy in finally.
Run when no one is editing blacklist settings. Never print existing policy contents.
"""
import hashlib
import json
import os
from pathlib import Path
import pwd
import sqlite3
import subprocess
import sys
import tempfile

repo = Path(__file__).resolve().parents[1]
cli = Path(sys.argv[1]).resolve() if len(sys.argv) > 1 else repo / 'Native/GreenBubbles/target/release/greenbubbles'
policy = Path(pwd.getpwuid(os.getuid()).pw_dir) / 'Library/Application Support/GreenBubbles/ai-read-policy.json'
policy.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
original = policy.read_bytes() if policy.exists() else None
original_mode = policy.stat().st_mode & 0o777 if policy.exists() else None
checks = {}

def write_policy(data):
    fd, name = tempfile.mkstemp(dir=policy.parent)
    try:
        os.write(fd, data)
        os.fsync(fd)
        os.close(fd)
        os.replace(name, policy)
    finally:
        if Path(name).exists(): Path(name).unlink()

def verify(name, ok):
    checks[name] = bool(ok)
    if not ok: raise AssertionError(name)

try:
    with tempfile.TemporaryDirectory(prefix='greenbubbles-policy-e2e-') as folder:
        root = Path(folder)
        ids = ['wxid_policy_e2e_denied', 'policy_e2e_denied@chatroom', 'wxid_policy_e2e_allowed', 'wxid_policy_e2e_allowed2']
        for part in ('contact', 'session', 'message'): (root / part).mkdir()
        with sqlite3.connect(root / 'contact/contact.db') as db:
            db.execute('CREATE TABLE contact(username TEXT PRIMARY KEY, alias TEXT, remark TEXT, nick_name TEXT)')
            db.executemany('INSERT INTO contact VALUES (?, ?, ?, ?)', [(i, '', 'Forbidden Fixture' if n < 2 else 'Allowed Fixture '+str(n), '') for n, i in enumerate(ids)])
        with sqlite3.connect(root / 'session/session.db') as db:
            db.execute('CREATE TABLE SessionTable(username TEXT, sort_timestamp INTEGER, summary TEXT)')
            db.executemany('INSERT INTO SessionTable VALUES (?, ?, ?)', [(i, 100-n, 'DENIED_CONTENT' if n < 2 else 'ALLOWED_CONTENT') for n, i in enumerate(ids)])
        with sqlite3.connect(root / 'message/message_0.db') as db:
            db.execute('CREATE TABLE Name2Id(user_name TEXT)')
            db.execute("INSERT INTO Name2Id VALUES ('wxid_synthetic_sender')")
            for n, identifier in enumerate(ids):
                table = 'Msg_' + hashlib.md5(identifier.encode()).hexdigest()
                db.execute(f'CREATE TABLE [{table}](server_id INTEGER, sort_seq INTEGER, local_type INTEGER, real_sender_id INTEGER, create_time INTEGER, status INTEGER, message_content BLOB, packed_info_data BLOB, WCDB_CT_message_content INTEGER, compress_content BLOB)')
                db.execute(f'INSERT INTO [{table}] VALUES (1, 1, 1, 1, 1700000000, 0, ?, NULL, 0, NULL)', ('DENIED_CONTENT' if n < 2 else 'ALLOWED_CONTENT',))
        def run(*args, environment=None):
            return subprocess.run([str(cli), *map(str,args)], capture_output=True, env=environment, timeout=30)
        # Preserve any existing decisions while adding synthetic denied identifiers.
        saved = json.loads(original)['conversationIds'] if original else []
        document = json.dumps({'version':1,'conversationIds':sorted(set(saved + ids[:2]))}).encode()
        write_policy(document)
        first = run('chats','list',root,'--decrypted','--limit','1')
        value = json.loads(first.stdout)
        verify('catalog-excludes-denied-summary', first.returncode == 0 and b'DENIED_CONTENT' not in first.stdout and value['items'][0]['id'] == ids[2])
        second = run('chats','list',root,'--decrypted','--limit','1','--cursor',value['page']['nextCursor'])
        verify('filtered-pagination-continuity', json.loads(second.stdout)['items'][0]['id'] == ids[3])
        contact = run('contacts','list',root,'--decrypted','--details')
        verify('contacts-excluded', contact.returncode == 0 and all(i.encode() not in contact.stdout for i in ids[:2]))
        found = run('chats','find','Forbidden Fixture',root,'--decrypted')
        verify('name-lookup-no-leak', found.returncode == 0 and all(i.encode() not in found.stdout + found.stderr for i in ids[:2]))
        for n, identifier in enumerate(ids[:2]):
            result = run('messages','list',root,'--decrypted','--conversation',identifier)
            verify('denied-group' if n else 'denied-person', result.returncode != 0 and b'DENIED_CONTENT' not in result.stdout)
        allowed = run('messages','list',root,'--decrypted','--conversation',ids[2])
        verify('allowed-chat-still-readable', allowed.returncode == 0 and b'ALLOWED_CONTENT' in allowed.stdout)
        batch = run('messages','list',root,'--decrypted','--conversation',ids[2],'--conversation',ids[0])
        verify('mixed-batch-no-partial-disclosure', batch.returncode != 0 and b'DENIED_CONTENT' not in batch.stdout)
        search = run('messages','search',root,'--decrypted','--query','CONTENT')
        verify('global-search-fails-closed', search.returncode != 0 and b'aiReadDenied' in search.stdout)
        for command in ('ai-export', 'ai-query', 'memory', 'replica-query', 'connector-serve', 'chats'):
            args = [command, 'rank', root, '--decrypted'] if command == 'chats' else [command]
            result = run(*args)
            verify('bulk-guard-'+command, result.returncode != 0 and b'blacklist' in result.stdout + result.stderr)
        media = run('attachment','inspect',root,'--conversation',ids[0],'--md5','0'*32)
        verify('attachment-denied-before-read', media.returncode != 0 and b'blacklist' in media.stdout + media.stderr)
        environment = dict(os.environ, HOME=folder, GREENBUBBLES_NATIVE_UI='1')
        spoof = run('messages','list',root,'--decrypted','--conversation',ids[0], environment=environment)
        verify('environment-cannot-bypass', spoof.returncode != 0 and b'DENIED_CONTENT' not in spoof.stdout)
        write_policy(b'{invalid')
        corrupt = run('chats','list',root,'--decrypted')
        verify('corrupt-policy-fails-closed', corrupt.returncode != 0)
        write_policy(document)
        policy.chmod(0o644)
        insecure = run('chats','list',root,'--decrypted')
        verify('insecure-policy-fails-closed', insecure.returncode != 0)
        write_policy(json.dumps({'version':1,'conversationIds':saved}).encode())
        unblocked = run('messages','list',root,'--decrypted','--conversation',ids[0])
        verify('unblocking-restores-read', unblocked.returncode == 0 and b'DENIED_CONTENT' in unblocked.stdout)
finally:
    if original is None:
        policy.unlink(missing_ok=True)
    else:
        write_policy(original)
        policy.chmod(original_mode)
    destination = repo / 'docs/acceptance/ai-read-blacklist/cli-e2e.json'
    destination.parent.mkdir(parents=True, exist_ok=True)
    destination.write_text(json.dumps({'syntheticOnly':True, 'policyRestored':True,'checks':checks, 'passed':bool(checks) and all(checks.values())}, indent=2)+'\n')
print(json.dumps({'checks':len(checks),'passed':all(checks.values()),'artifact':str(destination)}))
