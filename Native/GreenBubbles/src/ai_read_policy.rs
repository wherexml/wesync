//! User-owned deny policy. No command-line or environment bypass.
use crate::live_query::LiveQueryError;
use serde::Deserialize;
use std::os::unix::fs::MetadataExt;
use std::{collections::BTreeSet, fs, path::PathBuf};

#[derive(Deserialize)]
#[serde(deny_unknown_fields, rename_all = "camelCase")]
struct Document {
    version: u32,
    conversation_ids: BTreeSet<String>,
}

fn denied() -> LiveQueryError {
    LiveQueryError::AiReadDenied
}

pub fn policy_path() -> Result<PathBuf, LiveQueryError> {
    // Resolve the OS account, not HOME supplied by an agent process.
    let home = unsafe {
        let entry = libc::getpwuid(libc::getuid());
        if entry.is_null() {
            return Err(denied());
        }
        std::ffi::CStr::from_ptr((*entry).pw_dir)
            .to_str()
            .map_err(|_| denied())?
            .to_owned()
    };
    Ok(PathBuf::from(home).join("Library/Application Support/GreenBubbles/ai-read-policy.json"))
}

pub fn load() -> Result<BTreeSet<String>, LiveQueryError> {
    let path = policy_path()?;
    let metadata = match fs::symlink_metadata(&path) {
        Ok(value) => value,
        Err(e) if e.kind() == std::io::ErrorKind::NotFound => return Ok(BTreeSet::new()),
        Err(_) => return Err(denied()),
    };
    if !metadata.is_file()
        || metadata.file_type().is_symlink()
        || metadata.uid() != unsafe { libc::getuid() }
        || metadata.mode() & 0o077 != 0
        || metadata.len() > 4 * 1024 * 1024
    {
        return Err(denied());
    }
    let doc: Document =
        serde_json::from_slice(&fs::read(path).map_err(|_| denied())?).map_err(|_| denied())?;
    if doc.version != 1 || doc.conversation_ids.iter().any(|id| id.is_empty()) {
        return Err(denied());
    }
    Ok(doc.conversation_ids)
}

// Only the installed, signed app's direct children retain human browsing access.
// Both the app and bundled CLI must share a certificate, and ad-hoc signatures fail.
#[cfg(target_os = "macos")]
fn native_parent() -> bool {
    use std::process::Command;
    unsafe extern "C" {
        fn proc_pidpath(pid: i32, buffer: *mut libc::c_void, size: u32) -> i32;
    }
    let mut path = [0u8; 4096];
    let n = unsafe { proc_pidpath(libc::getppid(), path.as_mut_ptr().cast(), path.len() as u32) };
    if n <= 0 {
        return false;
    }
    let parent = std::ffi::CStr::from_bytes_until_nul(&path)
        .ok()
        .and_then(|p| p.to_str().ok());
    let app = "/Applications/GreenBubbles.app";
    if parent != Some("/Applications/GreenBubbles.app/Contents/MacOS/greenbubbles-history") {
        return false;
    }
    let Ok(exe) = std::env::current_exe() else {
        return false;
    };
    if exe != PathBuf::from(app).join("Contents/MacOS/greenbubbles")
        && exe != PathBuf::from(app).join("Contents/MacOS/greenbubbles-sticker-query")
    {
        return false;
    }
    let Ok(details) = Command::new("/usr/bin/codesign")
        .args(["-d", "-r-", app])
        .output()
    else {
        return false;
    };
    let detail = format!(
        "{}\n{}",
        String::from_utf8_lossy(&details.stdout),
        String::from_utf8_lossy(&details.stderr)
    );
    let Some(requirement) = detail
        .lines()
        .find_map(|s| s.strip_prefix("designated => "))
    else {
        return false;
    };
    if !requirement.contains("certificate") {
        return false;
    }
    if !Command::new("/usr/bin/codesign")
        .args(["--verify", "--strict", "--deep", app])
        .output()
        .is_ok_and(|o| o.status.success())
    {
        return false;
    }
    // Verify CLI certificate against the app's certificate part, retaining its own identifier.
    let Some((_, cert)) = requirement.split_once(" and ") else {
        return false;
    };
    Command::new("/usr/bin/codesign")
        .args(["--verify", "--strict", "-R", &format!("={cert}")])
        .arg(exe)
        .output()
        .is_ok_and(|o| o.status.success())
}
#[cfg(not(target_os = "macos"))]
fn native_parent() -> bool {
    false
}

pub fn effective() -> Result<BTreeSet<String>, LiveQueryError> {
    static NATIVE: std::sync::OnceLock<bool> = std::sync::OnceLock::new();
    if *NATIVE.get_or_init(native_parent) {
        return Ok(BTreeSet::new());
    }
    load()
}
pub fn require_conversation(id: &str) -> Result<(), LiveQueryError> {
    if effective()?.contains(id) {
        Err(denied())
    } else {
        Ok(())
    }
}
pub fn require_unrestricted() -> Result<(), LiveQueryError> {
    if effective()?.is_empty() {
        Ok(())
    } else {
        Err(denied())
    }
}
pub fn check_command(command: &str) -> Result<(), LiveQueryError> {
    if matches!(
        command,
        "help"
            | "chats"
            | "conversations"
            | "contacts"
            | "messages"
            | "message"
            | "attachment"
            | "source"
    ) {
        // Even an allowed operation fails closed when the policy cannot be read.
        effective()?;
        Ok(())
    } else {
        require_unrestricted()
    }
}
pub fn check_connector() -> Result<(), crate::connector::ConnectorErrorBody> {
    require_unrestricted().map_err(|_| crate::connector::ConnectorErrorBody {
        code: crate::connector::ConnectorErrorCode::Unauthorized,
        message: "AI read blacklist denies this connector operation".into(),
        retryable: false,
    })
}
