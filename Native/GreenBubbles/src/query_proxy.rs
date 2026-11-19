//! Private, bounded transport for the application's existing read-only CLI.
use serde::{Deserialize, Serialize};
use std::fs;
use std::io::{Read, Write};
use std::os::unix::fs::{FileTypeExt, MetadataExt, PermissionsExt};
use std::os::unix::net::{UnixListener, UnixStream};
use std::path::{Path, PathBuf};
use std::time::Duration;

#[derive(Debug, thiserror::Error)]
#[error("we-sync query proxy unavailable. The background connection could not be restored; ask the user to open settings manually if setup is needed. Do not activate a window or grant disk access to the AI app.")]
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
    let bytes = serde_json::to_vec(request)?;
    if bytes.len() as u64 > MAX_REQUEST {
        return Err("Proxy request exceeds limit".into());
    }
    // Start only before a connection exists. Never replay a request after writing it.
    let path = socket_path()?;
    let mut stream = match connect(&path) {
        Ok(stream) => stream,
        Err(_) => start_and_connect(&path)?,
    };
    stream.set_read_timeout(Some(Duration::from_secs(75)))?;
    stream.set_write_timeout(Some(Duration::from_secs(10)))?;
    stream.write_all(&bytes)?;
    stream.shutdown(std::net::Shutdown::Write)?;
    read(&mut stream, MAX_RESPONSE)
}
fn connect(path: &Path) -> Result<UnixStream, Box<dyn std::error::Error>> {
    private(path.parent().ok_or("Missing socket directory")?, false)?;
    private(path, true)?;
    let stream = UnixStream::connect(path)?;
    if !same_user(&stream) {
        return Err("Untrusted query proxy".into());
    }
    Ok(stream)
}

#[cfg(not(target_os = "macos"))]
fn start_and_connect(_path: &Path) -> Result<UnixStream, Box<dyn std::error::Error>> {
    Err(Unavailable.into())
}

#[cfg(target_os = "macos")]
fn start_and_connect(path: &Path) -> Result<UnixStream, Box<dyn std::error::Error>> {
    use std::os::fd::AsRawFd;
    use std::os::unix::fs::{DirBuilderExt, OpenOptionsExt};
    use std::process::{Command, Stdio};
    use std::time::Instant;
    let directory = path.parent().ok_or("Missing socket directory")?;
    fs::DirBuilder::new()
        .recursive(true)
        .mode(0o700)
        .create(directory)?;
    private(directory, false)?;
    // Refuse an unsafe pre-existing endpoint instead of launching over it.
    if fs::symlink_metadata(path).is_ok() {
        private(path, true)?;
    }
    let lock = fs::OpenOptions::new()
        .read(true)
        .write(true)
        .create(true)
        .truncate(false)
        .mode(0o600)
        .custom_flags(libc::O_NOFOLLOW)
        .open(directory.join("query-start.lock"))?;
    let metadata = lock.metadata()?;
    if !metadata.is_file()
        || metadata.uid() != unsafe { libc::getuid() }
        || metadata.mode() & 0o077 != 0
    {
        return Err(Unavailable.into());
    }
    let deadline = Instant::now() + Duration::from_secs(25);
    while unsafe { libc::flock(lock.as_raw_fd(), libc::LOCK_EX | libc::LOCK_NB) } != 0 {
        if Instant::now() >= deadline {
            return Err(Unavailable.into());
        }
        if let Ok(stream) = connect(path) {
            return Ok(stream);
        }
        std::thread::sleep(Duration::from_millis(100));
    }
    if let Ok(stream) = connect(path) {
        return Ok(stream);
    }
    let marker = directory.join("query-start-mode");
    let mut launch_marker = None;
    if !installed_app_running()? {
        if let Ok(metadata) = fs::symlink_metadata(&marker) {
            if !metadata.is_file()
                || metadata.uid() != unsafe { libc::getuid() }
                || metadata.mode() & 0o077 != 0
            {
                return Err(Unavailable.into());
            }
        }
        let timestamp = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)?
            .as_secs()
            .to_string();
        let mut file = fs::OpenOptions::new()
            .write(true)
            .create(true)
            .truncate(true)
            .mode(0o600)
            .custom_flags(libc::O_NOFOLLOW)
            .open(&marker)?;
        file.write_all(timestamp.as_bytes())?;
        launch_marker = Some(LaunchMarker {
            path: marker,
            content: timestamp,
        });
        let status = Command::new("/usr/bin/open")
            .args([
                "-g",
                "-j",
                "-a",
                "/Applications/we-sync.app",
                "--args",
                "--background-query",
            ])
            .stdin(Stdio::null())
            .stdout(Stdio::null())
            .stderr(Stdio::null())
            .status()?;
        if !status.success() {
            return Err(Unavailable.into());
        }
    }
    loop {
        if let Ok(stream) = connect(path) {
            drop(launch_marker);
            return Ok(stream);
        }
        if Instant::now() >= deadline {
            return Err(Unavailable.into());
        }
        std::thread::sleep(Duration::from_millis(100));
    }
}

#[cfg(target_os = "macos")]
struct LaunchMarker {
    path: PathBuf,
    content: String,
}
#[cfg(target_os = "macos")]
impl Drop for LaunchMarker {
    fn drop(&mut self) {
        if fs::read_to_string(&self.path).is_ok_and(|s| s == self.content) {
            let _ = fs::remove_file(&self.path);
        }
    }
}

#[cfg(target_os = "macos")]
fn installed_app_running() -> Result<bool, Box<dyn std::error::Error>> {
    unsafe extern "C" {
        fn proc_listpids(kind: u32, info: u32, buffer: *mut libc::c_void, size: i32) -> i32;
        fn proc_pidpath(pid: i32, buffer: *mut libc::c_void, size: u32) -> i32;
    }
    // The system process API works inside a caller sandbox where executing ps may not.
    // Only executable paths are inspected; arguments and credentials are never read.
    let mut pids = vec![0_i32; 65_536];
    let capacity = (pids.len() * std::mem::size_of::<i32>()) as i32;
    let bytes = unsafe { proc_listpids(1, 0, pids.as_mut_ptr().cast(), capacity) };
    if bytes <= 0 || bytes >= capacity {
        return Err(Unavailable.into());
    }
    let installed = "/Applications/we-sync.app/Contents/MacOS/greenbubbles-history";
    for pid in pids
        .into_iter()
        .take(bytes as usize / std::mem::size_of::<i32>())
    {
        if pid <= 0 {
            continue;
        }
        let mut path = [0_u8; 4096];
        if unsafe { proc_pidpath(pid, path.as_mut_ptr().cast(), path.len() as u32) } > 0
            && std::ffi::CStr::from_bytes_until_nul(&path)
                .is_ok_and(|p| p.to_bytes() == installed.as_bytes())
        {
            return Ok(true);
        }
    }
    Ok(false)
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
