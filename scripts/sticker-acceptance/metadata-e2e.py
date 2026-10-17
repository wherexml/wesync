#!/usr/bin/env python3
"""Repeatable CLI E2E: exact-message metadata, source isolation and bounded fields."""
import hashlib, json, pathlib, sqlite3, subprocess, sys, tempfile
cli = str(pathlib.Path(sys.argv[1]).resolve())
checks = {}
with tempfile.TemporaryDirectory() as tmp:
    root = pathlib.Path(tmp)
    for name in ('message','session','contact','emoticon'):
        (root/name).mkdir()
    digest = hashlib.md5(b'synthetic-sticker').hexdigest()
    table = 'Msg_'+hashlib.md5(b'wxid_fixture').hexdigest()
    con = sqlite3.connect(root/'message/message_0.db')
    con.execute('CREATE TABLE Name2Id(user_name TEXT)')
    con.execute("INSERT INTO Name2Id VALUES ('sender')")
    con.execute(f'CREATE TABLE [{table}](server_id INTEGER,sort_seq INTEGER,local_type INTEGER,real_sender_id INTEGER,create_time INTEGER,status INTEGER,message_content TEXT,packed_info_data BLOB,WCDB_CT_message_content INTEGER,compress_content BLOB)')
    xml = f'<msg><emoji md5="{digest}" type="2"/></msg>'
    con.execute(f'INSERT INTO [{table}] VALUES(42,100,47,1,1000,0,?,NULL,0,NULL)',(xml,))
    con.commit();con.close()
    con=sqlite3.connect(root/'session/session.db');con.execute('CREATE TABLE SessionTable(username TEXT,sort_timestamp INTEGER)');con.execute("INSERT INTO SessionTable VALUES('wxid_fixture',1000)");con.commit();con.close()
    con=sqlite3.connect(root/'contact/contact.db');con.execute('CREATE TABLE contact(username TEXT,alias TEXT,remark TEXT,nick_name TEXT)');con.commit();con.close()
    def run(args):
        for db in root.rglob('*.db'): db.chmod(0o600)
        result=subprocess.run([cli]+args,capture_output=True,text=True)
        if result.returncode: raise RuntimeError('Synthetic CLI failed: '+result.stdout[:200])
        return json.loads(result.stdout)
    page=run(['messages','list',str(root),'--decrypted','--conversation','wxid_fixture','--limit','1','--json'])
    message=page['items'][0]['id']
    args=['message','get',str(root),'--decrypted','--conversation','wxid_fixture','--message',message]
    original=run(args)
    checks['missing-database-keeps-message']='StickerResource' not in original['item']['content']
    con=sqlite3.connect(root/'emoticon/emoticon.db');con.execute('CREATE TABLE kNonStoreEmoticonTable(md5 TEXT PRIMARY KEY,cdn_url TEXT,aes_key TEXT,encrypt_url TEXT)');con.execute('INSERT INTO kNonStoreEmoticonTable VALUES(?,?,?,?)',(digest,'https://emoji.qpic.cn/synthetic','0'*32,'https://emoji.qpic.cn/encrypted'));con.commit()
    recovered=run(args)
    checks['exact-md5-row']=recovered['item']['content']['StickerResource']['md5']==digest
    checks['raw-message-preserved']=recovered['item']['content']['Emoji']==xml
    checks['database-accounted']=recovered['consistency']['databaseCount']==original['consistency']['databaseCount']+1
    con.execute('UPDATE kNonStoreEmoticonTable SET cdn_url=?',('x'*5000,));con.commit()
    checks['oversized-field-rejected']='cdnurl' not in run(args)['item']['content']['StickerResource']
    con.execute('UPDATE kNonStoreEmoticonTable SET md5=?',('a'*32,));con.commit()
    checks['unrelated-row-not-used']='StickerResource' not in run(args)['item']['content']
    con.close()
report={'passed':all(checks.values()),'checks':checks,'privateDataRecorded':False}
pathlib.Path(sys.argv[2]).write_text(json.dumps(report,indent=2)+'\n')
assert report['passed'], report
print('Metadata CLI E2E:',len(checks),'PASS')
