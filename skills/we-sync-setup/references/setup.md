# Setup and recovery

## Reinstall or verify

1. To install or update the two skills from a project checkout or bundle, run
   `python3 scripts/install-skills.py --agent codex --update` from its root.
   Restart the agent session to refresh discovery. Keep existing local edits
   by moving conflicting skill folders out of discovery before reinstalling.
2. Run the doctor in `we-sync-setup/scripts/doctor.py`. It uses the specified
   binary or `GREENBUBBLES_CLI`, otherwise `greenbubbles` on PATH or the
   installed `/Applications/we-sync.app` tool when PATH has no match.
   A working source is ready to use. There is no profile to initialize for the
   usual single account, and a skills reinstall does not affect credentials.
3. For a desktop app reinstall, use the same trusted signing identity and
   preserve the Bundle ID and remembered connection. Follow the project's
   `docs/LOCAL_SIGNING.md` for signed tool migration and native cold-start
   verification. If macOS displays a permission prompt, the owner can approve
   that specific prompt.

## Fix a failed check

- **Missing or incompatible tool:** repair the installed app or install the Rust
  CLI. From source, build with
  `cargo build --locked --release --manifest-path Native/GreenBubbles/Cargo.toml`,
  then pass `Native/GreenBubbles/target/release/greenbubbles` to the doctor.
  A similarly named discovery executable may lack message queries. If a binary
  is found but fails validation, check it explicitly rather than switching to
  another tool to circumvent a failure or policy.
- **Source unavailable:** check that the expected local account or snapshot
  is accessible in this agent host. If macOS denies filesystem access, compare
  the owner terminal with the agent host and retry after the owner grants access.
  Check existing credentials and source selection before considering capture.
  Do not inspect key contents or enumerate Keychain.
- **Other account or snapshot:** use an existing named profile. Verify with
  `greenbubbles source status --profile NAME`. If a profile is needed, use
  `profile path` and `profile template`; preserve the existing default and
  profiles. Save only absolute paths and mode in the config, using a private
  directory and file. See the project's `docs/QUERY_PROFILES.md` for the schema.

For a nondefault live source or key file without multiple profiles,
`~/.greenbubbles/config.toml` supports these fields. Omit either line to use the
corresponding default.

```toml
[source]
root = "/absolute/path/to/db_storage"
passphrase_file = "/absolute/private/path/passphrase.txt"
```

## First connection

The CLI uses the existing private key file (normally
`~/.greenbubbles-acquire/passphrase.txt`, owner-only mode `0600`).
The desktop app keeps its own saved connection in macOS Keychain after a
successful connection. If only the CLI is set up and the desktop app needs
a connection, enter the verified database key once in the app's native form.
If only the app works, use an existing authorized CLI key file or report the
missing CLI credential. Do not export the app's Keychain item or make a new
plaintext copy from it. A key for an old account does not authorize a new one.

When neither a verified credential nor a usable backup exists, refer the
owner to the project's `docs/PASSPHRASE_ACQUISITION.md`. Initial live capture
may require admin authorization, re-signing and restarting WeChat, and a new
login. These steps are separate from reinstall and must be performed by the
owner. After capture, rerun the doctor without exposing the saved key.
