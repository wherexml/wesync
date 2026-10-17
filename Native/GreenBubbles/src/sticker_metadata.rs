//! Exact-message sticker metadata enrichment. Never enumerates stickers or writes a database.
use crate::live_query::{LiveQuerySource, MessageItem};
use rusqlite::{params, OptionalExtension};
use serde_json::{Map, Value};
use std::path::Path;

/// Returns whether an additional database was opened. Missing metadata is non-fatal.
pub fn enrich(source: &LiveQuerySource<'_>, message: &mut MessageItem) -> bool {
    if message.message_type != 47 {
        return false;
    }
    let Some(raw) = message.content.get("Emoji").and_then(Value::as_str) else {
        return false;
    };
    if raw.len() > 256 * 1024 {
        return false;
    }
    let Ok(xml) = roxmltree::Document::parse(raw) else {
        return false;
    };
    let Some(emoji) = xml.descendants().find(|n| n.has_tag_name("emoji")) else {
        return false;
    };
    let Some(md5) = emoji
        .attribute("md5")
        .filter(|v| v.len() == 32 && v.bytes().all(|b| b.is_ascii_hexdigit()))
    else {
        return false;
    };
    let md5 = md5.to_ascii_lowercase();
    let Ok(Some(connection)) = source.open_optional_database(Path::new("emoticon/emoticon.db"))
    else {
        return false;
    };
    // Bound database work as well as returned data, including unindexed/incompatible sources.
    let mut steps = 0;
    if connection
        .progress_handler(
            1000,
            Some(move || {
                steps += 1;
                steps > 1000
            }),
        )
        .is_err()
    {
        return true;
    }
    let columns = [
        "md5",
        "cdn_url",
        "encrypt_url",
        "aes_key",
        "thumb_url",
        "extern_url",
        "extern_md5",
    ];
    let mut schema = match connection.prepare("PRAGMA table_info(kNonStoreEmoticonTable)") {
        Ok(s) => s,
        Err(_) => return true,
    };
    let Ok(rows) = schema.query_map([], |row| row.get::<_, String>(1)) else {
        return true;
    };
    let present: Vec<String> = rows.filter_map(Result::ok).take(256).collect();
    if !present.iter().any(|c| c == "md5") {
        return true;
    }
    let select: Vec<String> = columns.iter().map(|c| {
        if present.iter().any(|p| p == c) {
            format!("CASE WHEN length(CAST([{c}] AS BLOB)) <= 4096 THEN CAST([{c}] AS TEXT) ELSE NULL END")
        } else { "NULL".into() }
    }).collect();
    let sql = format!(
        "SELECT {} FROM kNonStoreEmoticonTable WHERE md5 = ?1 COLLATE NOCASE LIMIT 1",
        select.join(",")
    );
    let result = connection
        .query_row(&sql, params![md5], |row| {
            let mut metadata = Map::new();
            for (index, name) in [
                "md5",
                "cdnurl",
                "encrypturl",
                "aeskey",
                "thumburl",
                "externurl",
                "externmd5",
            ]
            .iter()
            .enumerate()
            {
                if let Some(value) = row.get::<_, Option<String>>(index)? {
                    if !value.is_empty() {
                        metadata.insert((*name).into(), Value::String(value));
                    }
                }
            }
            Ok(metadata)
        })
        .optional();
    if let Ok(Some(metadata)) = result {
        if metadata
            .get("md5")
            .and_then(Value::as_str)
            .is_some_and(|v| v.eq_ignore_ascii_case(&md5))
        {
            if let Some(content) = message.content.as_object_mut() {
                content.insert("StickerResource".into(), Value::Object(metadata));
            }
        }
    }
    true
}
