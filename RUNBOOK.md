# P25 Monitor — release runbook

Everything you need to push a new TestFlight build. Do this on the **Mac** (signing
needs the Xcode GUI keychain — it cannot be done over SSH).

## Push a new build to TestFlight

```bash
cd ~/src/p25-ios
git reset --hard origin/main    # discard local project churn (safe: Secrets.swift is gitignored)
git pull                        # get the latest committed code
./release.sh                    # sets a fresh build number + regenerates the project
open P25Monitor.xcodeproj
```

Then in Xcode:
1. Set the run target to **Any iOS Device (arm64)** (top bar, next to the scheme).
2. **Product ▸ Archive** — wait for it to build and sign.
3. In the **Organizer** window that opens: **Distribute App ▸ TestFlight & App Store ▸ Upload**.

That's it. The build number is a timestamp, so it never collides with a previous upload.

## Bump the visible version number (optional)

TestFlight only needs a unique *build* number (handled automatically). To change the
**marketing version** users see (e.g. 1.0 → 1.1), edit one line in `project.yml`:

```yaml
CFBundleShortVersionString: "1.1"
```
then re-run `./release.sh`.

## Signing / CarPlay — how it works (so you don't have to relearn it)

- Signing is **automatic** (Xcode-managed). Team ID **634QAM3ZHG** is pinned in
  `project.yml`, so `xcodegen` no longer wipes it.
- **CarPlay** (`com.apple.developer.carplay-driving-task`) lives **only** in
  `P25Monitor/P25Monitor.entitlements`. It does **not** appear as a capability chip in
  Xcode's "Signing & Capabilities" tab — that's normal. Your Apple account is approved
  for it, and Xcode's managed provisioning profile already includes it.
- The entitlements file must contain **exactly** the CarPlay key and nothing it can't
  provision. Adding an entitlement the profile can't satisfy (e.g. `aps-environment`
  for push before Push is enabled on the App ID) makes Xcode silently strip the file to
  `<dict/>` — which is what "CarPlay disappeared" looks like. If that happens:
  ```bash
  git checkout -- P25Monitor/P25Monitor.entitlements
  ```

## If Signing shows a red error in Xcode

1. Target **P25Monitor ▸ Signing & Capabilities**.
2. Tick **Automatically manage signing**, select your team (**634QAM3ZHG**).
3. If it still complains, **Xcode ▸ Settings ▸ Accounts ▸ Download Manual Profiles**,
   then clean build (⇧⌘K) and Archive again.

## Push notifications (currently OFF, on purpose)

The push code is in the app but inert — the `aps-environment` entitlement was removed
because it broke CarPlay signing. To enable push later: enable **Push Notifications** on
the App ID at developer.apple.com, add `aps-environment` = **production** back to the
entitlements file, then archive. The server-side APNs key is already provisioned.
