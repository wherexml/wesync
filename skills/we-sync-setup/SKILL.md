---
name: we-sync-setup
description: Set up or reinstall the we-sync skills and verify local read-only WeChat access. Use for missing tools, first connection, or failed reconnection. Prefer an existing saved connection.
---

# Set up we-sync

Start with the content-free connection check. It selects the configured CLI
or the installed app's bundled tool and never asks for a key.

```sh
python3 scripts/doctor.py
```

Resolve the script from this skill directory. Use `--greenbubbles PATH` for a
specific executable or `--profile NAME` for an already configured alternate
source. If the doctor succeeds, setup is complete. Use its reported binary
with [we-search](../we-search/SKILL.md).

If the check fails, use [setup and recovery](references/setup.md) for the
specific failure. Keep the desktop app's remembered connection and the CLI's
existing private credential. Diagnose tool path, account selection, and macOS
permissions before considering a new credential. A reinstall is not a reason to
clear settings or reacquire a key.

On first setup, an existing private key file can serve the CLI without typing.
If the desktop app has no saved connection, enter the verified database key
once in its native connection form. Keep secrets out of chat, arguments, and
logs. Only the owner can perform first-time capture when no verified credential
exists. Do not attach to, re-sign, restart, or operate WeChat during setup.
