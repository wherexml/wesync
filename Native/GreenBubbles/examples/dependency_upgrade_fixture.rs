//! Synthetic encrypted source for cross-version CLI E2E; key arrives on stdin.
use rusqlite::Connection;
use std::{fs, io, os::unix::fs::PermissionsExt, path::PathBuf};
use zeroize::Zeroizing;

fn main() -> Result<(), Box<dyn std::error::Error>> {
    let root = PathBuf::from(std::env::args().nth(1).ok_or("missing fixture root")?);
    let mut input = Zeroizing::new(String::new());
    io::stdin().read_line(&mut input)?;
    let key = Zeroizing::new(hex::decode(input.trim())?);
    if key.len() != 32 {
        return Err("fixture key must be 32 bytes".into());
    }
    fs::create_dir(&root)?;
    fs::set_permissions(&root, fs::Permissions::from_mode(0o700))?;
    let conversation = "wxid_dependency_fixture";
    let table = format!("Msg_{:x}", md5::compute(conversation));
    let definitions = [
        ("message/message_0.db", format!(
            "CREATE TABLE Name2Id(user_name TEXT);
             INSERT INTO Name2Id VALUES ('synthetic_sender');
             CREATE TABLE [{table}](server_id INTEGER,sort_seq INTEGER,local_type INTEGER,real_sender_id INTEGER,create_time INTEGER,status INTEGER,message_content TEXT,packed_info_data BLOB,WCDB_CT_message_content INTEGER,compress_content BLOB);
             INSERT INTO [{table}] VALUES(42,100,1,1,1000,0,'synthetic dependency roundtrip',NULL,0,NULL);"
        )),
        ("session/session.db", format!(
            "CREATE TABLE SessionTable(username TEXT,sort_timestamp INTEGER);
             INSERT INTO SessionTable VALUES ('{conversation}',1000);"
        )),
        ("contact/contact.db", "CREATE TABLE contact(username TEXT,alias TEXT,remark TEXT,nick_name TEXT);".to_string()),
    ];
    for (relative, sql) in definitions {
        let path = root.join(relative);
        fs::create_dir(path.parent().ok_or("missing parent")?)?;
        fs::set_permissions(path.parent().unwrap(), fs::Permissions::from_mode(0o700))?;
        let connection = Connection::open(&path)?;
        // Matches the existing encrypted-source CLI fixture's SQLCipher API.
        let result = unsafe {
            rusqlite::ffi::sqlite3_key(connection.handle(), key.as_ptr().cast(), key.len() as i32)
        };
        if result != 0 {
            return Err("fixture key setup failed".into());
        }
        connection.execute_batch(&sql)?;
        drop(connection);
        fs::set_permissions(path, fs::Permissions::from_mode(0o600))?;
    }
    Ok(())
}
