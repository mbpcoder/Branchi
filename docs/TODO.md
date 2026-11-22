# TODO

Pending tasks that are blocked on something outside the code.

- [ ] **Snap Store: request classic confinement for `branchi`**
  - Blocked on: confirming the snapcraft.io / forum account.
  - Once confirmed, post `docs/snap-classic-request.md` in the "store-requests"
    category at https://forum.snapcraft.io.
  - Until approved, snap uploads from CI are held for manual review.
- [ ] **Windows code signing with SignPath Foundation** (removes the
  SmartScreen "Unknown publisher" warning). The release workflow signs
  automatically once these are set; until then releases stay unsigned.
  1. Apply at https://signpath.org/apply. The README's "Code signing policy"
     section covers the required policy text; check the team roles there.
  2. Turn on MFA for your GitHub and SignPath accounts.
  3. In SignPath, once approved: install the SignPath GitHub App on the repo,
     create artifact configurations with slugs `app` and `installer` from
     `.signpath/artifact-configurations/*.xml`, and note the signing policy
     slug (usually `release-signing`).
  4. In GitHub → Settings → Secrets and variables → Actions, add:
     - secret `SIGNPATH_API_TOKEN`
     - variables `SIGNPATH_ORGANIZATION_ID`, `SIGNPATH_PROJECT_SLUG`,
       `SIGNPATH_SIGNING_POLICY_SLUG`
  5. Each release then waits for you to approve two signing requests (app,
     then installer) in SignPath, within one hour each.
- [x] Add the `SNAPCRAFT_STORE_CREDENTIALS` GitHub Actions secret.
- [x] Merge `claude/amazing-lovelace-rpkkxu` into `main`, then push a `v0.1.0` tag to run the release.
