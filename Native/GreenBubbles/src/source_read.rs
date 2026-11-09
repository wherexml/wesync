//! Keep SQLite's WAL and shared-memory maintenance off source files.

use std::fs::{self, File, Metadata, OpenOptions, Permissions};
use std::io::{self, Read, Write};
use std::ops::{Deref, DerefMut};
use std::os::unix::fs::{MetadataExt, OpenOptionsExt, PermissionsExt};
use std::path::{Path, PathBuf};
use std::time::{Duration, Instant};

use rusqlite::Connection;
use tempfile::TempDir;

const COPY_LIMIT: u64 = 1024 * 1024 * 1024;
const COPY_TIMEOUT: Duration = Duration::from_secs(10);

pub(crate) struct DatabaseCopy {
    directory: TempDir,
}

pub(crate) struct SourceConnection {
    // Drop SQLite before removing its private files.
    connection: Connection,
    _copy: DatabaseCopy,
}

impl Deref for SourceConnection {
    type Target = Connection;

    fn deref(&self) -> &Connection {
        &self.connection
    }
}

impl DerefMut for SourceConnection {
    fn deref_mut(&mut self) -> &mut Connection {
        &mut self.connection
    }
}

impl DatabaseCopy {
    pub(crate) fn capture(source: &Path) -> io::Result<Self> {
        let mut wal = source.as_os_str().to_os_string();
        wal.push("-wal");
        let mut journal = source.as_os_str().to_os_string();
        journal.push("-journal");
        let sources = [source.to_path_buf(), wal.into(), journal.into()];
        let deadline = Instant::now() + COPY_TIMEOUT;
        let mut remaining = COPY_LIMIT;
        for _ in 0..2 {
            if let Some(copy) = Self::capture_once(&sources, deadline, &mut remaining)? {
                return Ok(copy);
            }
        }
        Err(io::Error::new(
            io::ErrorKind::WouldBlock,
            "database files changed during capture",
        ))
    }

    fn capture_once(
        sources: &[PathBuf; 3],
        deadline: Instant,
        remaining: &mut u64,
    ) -> io::Result<Option<Self>> {
        // Do not let TMPDIR redirect scratch writes into the source tree.
        let directory = tempfile::Builder::new()
            .prefix("we-sync-read-")
            .permissions(Permissions::from_mode(0o700))
            .tempdir_in("/tmp")?;
        let mut inputs = Vec::with_capacity(sources.len());
        for (index, path) in sources.iter().enumerate() {
            let file = match OpenOptions::new()
                .read(true)
                .custom_flags(libc::O_NOFOLLOW | libc::O_CLOEXEC | libc::O_NONBLOCK)
                .open(path)
            {
                Ok(file) => Some(file),
                Err(error) if index != 0 && error.kind() == io::ErrorKind::NotFound => None,
                Err(error) => return Err(error),
            };
            let stamp = file
                .as_ref()
                .map(|file| file.metadata().and_then(Stamp::from_metadata))
                .transpose()?;
            inputs.push((file, stamp));
        }
        // Bracket the entire DB/sidecar copy, including each sidecar's absence.
        // Never copy SHM: it is a disposable index into the WAL, not source data.
        if !names_match(sources, &inputs)? {
            return Ok(None);
        }
        for ((file, stamp), name) in
            inputs
                .iter_mut()
                .zip(["data.db", "data.db-wal", "data.db-journal"])
        {
            if let (Some(file), Some(stamp)) = (file, stamp) {
                if !copy_file(
                    file,
                    &directory.path().join(name),
                    stamp.size,
                    deadline,
                    remaining,
                )? {
                    return Ok(None);
                }
            }
        }
        if !names_match(sources, &inputs)? {
            return Ok(None);
        }
        Ok(Some(Self { directory }))
    }

    pub(crate) fn path(&self) -> PathBuf {
        self.directory.path().join("data.db")
    }

    pub(crate) fn bind(self, connection: Connection) -> SourceConnection {
        SourceConnection {
            connection,
            _copy: self,
        }
    }
}

#[derive(PartialEq, Eq)]
struct Stamp {
    device: u64,
    inode: u64,
    size: u64,
    modified: (i64, i64),
    changed: (i64, i64),
}

impl Stamp {
    fn from_metadata(metadata: Metadata) -> io::Result<Self> {
        if !metadata.is_file() || metadata.uid() != unsafe { libc::geteuid() } {
            return Err(io::Error::new(
                io::ErrorKind::InvalidData,
                "database and sidecars must be regular files owned by the current user",
            ));
        }
        Ok(Self {
            device: metadata.dev(),
            inode: metadata.ino(),
            size: metadata.len(),
            modified: (metadata.mtime(), metadata.mtime_nsec()),
            changed: (metadata.ctime(), metadata.ctime_nsec()),
        })
    }
}

fn names_match(sources: &[PathBuf], inputs: &[(Option<File>, Option<Stamp>)]) -> io::Result<bool> {
    for (path, (_, expected)) in sources.iter().zip(inputs) {
        let actual = match fs::symlink_metadata(path) {
            Ok(metadata) => Some(Stamp::from_metadata(metadata)?),
            Err(error) if error.kind() == io::ErrorKind::NotFound => None,
            Err(error) => return Err(error),
        };
        if actual.as_ref() != expected.as_ref() {
            return Ok(false);
        }
    }
    Ok(true)
}

fn copy_file(
    source: &mut File,
    destination: &Path,
    size: u64,
    deadline: Instant,
    remaining: &mut u64,
) -> io::Result<bool> {
    if Instant::now() >= deadline {
        return Err(io::Error::new(
            io::ErrorKind::TimedOut,
            "database capture timed out",
        ));
    }
    #[cfg(target_os = "macos")]
    {
        use std::ffi::CString;
        use std::os::fd::AsRawFd;
        use std::os::unix::ffi::OsStrExt;

        let path = CString::new(destination.as_os_str().as_bytes())?;
        // Clone the open descriptor so a replacement or symlink cannot
        // redirect capture. APFS clones do not copy the database's bytes.
        if unsafe { libc::fclonefileat(source.as_raw_fd(), libc::AT_FDCWD, path.as_ptr(), 0) } == 0
        {
            fs::set_permissions(destination, Permissions::from_mode(0o600))?;
            return Ok(true);
        }
        let error = io::Error::last_os_error();
        if !matches!(
            error.raw_os_error(),
            Some(libc::EXDEV | libc::ENOTSUP | libc::ENOSYS)
        ) {
            return Err(error);
        }
    }
    *remaining = remaining.checked_sub(size).ok_or_else(|| {
        io::Error::new(
            io::ErrorKind::FileTooLarge,
            "database capture exceeds the byte limit",
        )
    })?;
    let mut output = OpenOptions::new()
        .write(true)
        .create_new(true)
        .mode(0o600)
        .open(destination)?;
    let mut input = source.take(size);
    let mut buffer = [0; 64 * 1024];
    while input.limit() > 0 {
        if Instant::now() >= deadline {
            return Err(io::Error::new(
                io::ErrorKind::TimedOut,
                "database capture timed out",
            ));
        }
        let count = input.read(&mut buffer)?;
        if count == 0 {
            return Ok(false);
        }
        output.write_all(&buffer[..count])?;
    }
    Ok(true)
}
