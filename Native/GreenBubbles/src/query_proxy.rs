//! Private, bounded transport for the application's existing read-only CLI.
use serde::{Deserialize, Serialize};
use std::fs;
use std::io::{Read, Write};
use std::os::unix::fs::{FileTypeExt, MetadataExt, PermissionsExt};
use std::os::unix::net::{UnixListener, UnixStream};
use std::path::{Path, PathBuf};
use std::time::Duration;

#[derive(Debug, thiserror::Error)]
#[error("we-sync query proxy unavailable. Open we-sync and restore its connection; do not grant disk access to the AI app.")]
pub struct Unavailable;

pub const MAX_REQUEST: u64 = 64 * 1024;
pub const MAX_RESPONSE: u64 = 16 * 1024 * 1024;
#[derive(Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Request {
    pub arguments: Vec<String>,
    pub input: String,
}
#[derive(Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Response {
    pub status: i32,
    pub stdout: String,
    pub stderr: String,
}
pub fn socket_path() -> Result<PathBuf, Box<dyn std::error::Error>> {
    Ok(crate::ai_read_policy::policy_path()?.with_file_name("query.sock"))
}
// Only known read operations. Paths, credentials and profile overrides are never accepted.
pub fn source_position(args: &[String]) -> Result<usize, Box<dyn std::error::Error>> {
    let first = args.first().map(String::as_str).unwrap_or("");
    let second = args.get(1).map(String::as_str);
    let position = match (first, second) {
        ("source", Some("status")) => 2,
        ("source", None) => 1,
        ("chats" | "conversations", Some("find")) if args.get(2).is_some() => 3,
        ("chats" | "conversations", Some("list" | "rank")) => 2,
        ("chats" | "conversations", None) => 1,
        ("chats" | "conversations", Some(value)) if value.starts_with("--") => 1,
        ("contacts", Some("list")) => 2,
        ("contacts", None) => 1,
        ("messages", Some("list" | "search")) => 2,
        ("message", Some("get")) => 2,
        ("attachment", Some("inspect" | "materialize")) => 2,
        _ => return Err("Unsupported proxy query".into()),
    };
    let mut i = position;
    while i < args.len() {
        match args[i].as_str() {
            "--limit"
            | "--cursor"
            | "--since"
            | "--until"
            | "--conversation"
            | "--query"
            | "--message"
            | "--kind"
            | "--minimum-self-messages"
            | "--md5"
            | "--attachment"
            | "--output" => {
                i += 1;
                if i == args.len() {
                    return Err("Missing query option value".into());
                }
            }
            "--json" | "--brief" | "--redact" | "--details" | "--query-stdin" => (),
            _ => {
                return Err(
                    "Proxy accepts query options only; source and credentials belong to we-sync"
                        .into(),
                )
            }
        }
        i += 1;
    }
    Ok(position)
}
pub fn should_proxy(args: &[String]) -> bool {
    // Explicit offline sources remain an owner-managed compatibility interface.
    if args
        .iter()
        .any(|value| value.starts_with('/') || value.starts_with("./"))
    {
        // Values such as --output are not source positions.
        let position = match (
            args.first().map(String::as_str),
            args.get(1).map(String::as_str),
        ) {
            (Some("chats" | "conversations"), Some("find")) => 3,
            (Some("chats" | "conversations"), Some(v)) if v.starts_with("--") => 1,
            _ => 2,
        };
        if args.get(position).is_some_and(|v| !v.starts_with("--")) {
            return false;
        }
    }
    matches!(
        args.first().map(String::as_str),
        Some(
            "source"
                | "chats"
                | "conversations"
                | "contacts"
                | "messages"
                | "message"
                | "attachment"
        )
    ) && !args.iter().any(|v| {
        matches!(
            v.as_str(),
            "--profile"
                | "--decrypted"
                | "--passphrase-stdin"
                | "--snapshot-key-stdin"
                | "--snapshot-passphrase-stdin"
                | "--snapshot-recovery-kit"
                | "--snapshot-local-credential"
        )
    })
}

fn private(path: &Path, socket: bool) -> std::io::Result<()> {
    let m = fs::symlink_metadata(path)?;
    if m.uid() != unsafe { libc::getuid() }
        || m.mode() & 0o077 != 0
        || (socket && !m.file_type().is_socket())
        || (!socket && !m.is_dir())
    {
        return Err(std::io::Error::new(
            std::io::ErrorKind::PermissionDenied,
            "Unsafe query socket",
        ));
    }
    Ok(())
}
pub fn read<T: serde::de::DeserializeOwned>(
    stream: &mut UnixStream,
    limit: u64,
) -> Result<T, Box<dyn std::error::Error>> {
    let mut bytes = Vec::new();
    stream.take(limit + 1).read_to_end(&mut bytes)?;
    if bytes.len() as u64 > limit {
        return Err("Proxy envelope exceeds limit".into());
    }
    Ok(serde_json::from_slice(&bytes)?)
}
pub fn call(request: &Request) -> Result<Response, Box<dyn std::error::Error>> {
    let path = socket_path()?;
    private(path.parent().ok_or("Missing socket directory")?, false)?;
    private(&path, true)?;
    let mut stream = UnixStream::connect(path)?;
    if !same_user(&stream) {
        return Err("Untrusted query proxy".into());
    }
    stream.set_read_timeout(Some(Duration::from_secs(75)))?;
    stream.set_write_timeout(Some(Duration::from_secs(10)))?;
    let bytes = serde_json::to_vec(request)?;
    if bytes.len() as u64 > MAX_REQUEST {
        return Err("Proxy request exceeds limit".into());
    }
    stream.write_all(&bytes)?;
    stream.shutdown(std::net::Shutdown::Write)?;
    read(&mut stream, MAX_RESPONSE)
}
pub fn serve(
    path: &Path,
    mut handler: impl FnMut(Request) -> Response,
) -> Result<(), Box<dyn std::error::Error>> {
    private(path.parent().ok_or("Missing socket directory")?, false)?;
    if let Ok(m) = fs::symlink_metadata(path) {
        private(path, true)?;
        if UnixStream::connect(path).is_ok() {
            return Err("Query proxy already running".into());
        }
        // Only remove a stale, owned socket; never another type of file.
        if m.file_type().is_socket() {
            fs::remove_file(path)?;
        }
    }
    let listener = UnixListener::bind(path)?;
    fs::set_permissions(path, fs::Permissions::from_mode(0o600))?;
    for connection in listener.incoming() {
        let Ok(mut stream) = connection else { continue };
        if !same_user(&stream) {
            continue;
        }
        let _ = stream.set_read_timeout(Some(Duration::from_secs(3)));
        let _ = stream.set_write_timeout(Some(Duration::from_secs(10)));
        if let Ok(request) = read(&mut stream, MAX_REQUEST) {
            let response = handler(request);
            if let Ok(bytes) = serde_json::to_vec(&response) {
                if bytes.len() as u64 <= MAX_RESPONSE {
                    let _ = stream.write_all(&bytes);
                }
            }
        }
    }
    Ok(())
}

#[cfg(target_os = "macos")]
fn same_user(stream: &UnixStream) -> bool {
    use std::os::fd::AsRawFd;
    let mut uid = 0;
    let mut gid = 0;
    unsafe {
        libc::getpeereid(stream.as_raw_fd(), &mut uid, &mut gid) == 0 && uid == libc::getuid()
    }
}
#[cfg(not(target_os = "macos"))]
fn same_user(stream: &UnixStream) -> bool {
    use std::os::fd::AsRawFd;
    let mut credentials: libc::ucred = unsafe { std::mem::zeroed() };
    let mut size = std::mem::size_of::<libc::ucred>() as libc::socklen_t;
    unsafe {
        libc::getsockopt(
            stream.as_raw_fd(),
            libc::SOL_SOCKET,
            libc::SO_PEERCRED,
            (&mut credentials as *mut libc::ucred).cast(),
            &mut size,
        ) == 0
            && credentials.uid == libc::getuid()
    }
}
