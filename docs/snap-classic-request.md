# Classic confinement request: branchi

Post in the **store-requests** category at https://forum.snapcraft.io
(title: `Classic confinement request: branchi`).

---

Hi,

I'd like to request classic confinement for the snap **branchi**.

- **Snap name:** branchi
- **Source:** https://github.com/mbpcoder/Branchi
- **Description:** Branchi is a desktop git client (Rust core using libgit2, Flutter UI).
  It lets users browse history, stage and commit changes, edit files and manage branches
  in their local git repositories.

**Why classic confinement is needed**

Branchi falls under the supported category of *IDEs / development tools that need to
work with arbitrary user files and toolchains*:

1. **Arbitrary repository locations** – users keep repositories anywhere on the
   filesystem (e.g. `/srv`, `/opt`, `/var/www`, mounted volumes), not only under
   `$HOME`. Strict confinement with `home`/`removable-media` cannot cover this.
2. **Git configuration and credentials** – it must read the user's `~/.gitconfig`,
   `~/.git-credentials`, `~/.ssh/config` and SSH keys exactly as the `git` CLI does.
   The `home` interface does not expose hidden files, and `ssh-keys` is too
   restricted for typical setups (custom key paths, `ProxyCommand`, includes).
3. **Host tools** – git workflows rely on the host's SSH agent, credential helpers,
   GPG for commit signing, and repository hooks that run arbitrary host programs.
   These cannot work inside strict confinement.

This is the same reason other git clients and editors are published with classic
confinement.

Thanks for reviewing!
