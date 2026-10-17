---
name: wrap-app-permission
description: "Stop macOS permissions (Accessibility, Screen/Audio Recording) from resetting after each flake update by wrapping a Nix-store process in an .app with a fixed-identifier signature. Use for repeated permission prompts, TCC issues, or launchd agents such as sketchybar and cava, even if this skill is not named."
---

# Keep macOS permissions that reset on every update by wrapping the process in an .app

Even after you grant a macOS permission to a program installed with Nix, the permission comes off every time you update the flake and the prompt appears again.
Fix this by wrapping the program in an `.app`.

Argument: `<the target program or launchd agent>`. Example: `sketchybar`.

## Background: why it comes off (confirmed on the actual machine)

Every decision in the steps rests on this mechanism.

- TCC attaches a permission to the "responsible process". The responsible process is the first non-Apple executable exec'd after launchd's `/bin/sh`,
  and once decided it does not change on later execs. Permission requests from child processes (osascript and helper commands) are attributed to this responsible process.
- If the responsible process is not the main executable of an `.app`, the permission is recorded by the executable's "path".
  Nix store paths change on every update, so each time it becomes a different thing.
- For a shell-script wrapper (the product of `makeWrapper` or `wrapProgram`), the shebang's bash becomes the responsible process.
  The permission attaches not to the real binary but to a bash path that changes on nixpkgs updates. This is what was happening with sketchybar.
- For the main executable of an `.app`, tccd attributes it to the bundle ID (`BUNDLE_ATTRIBUTION` in the log).
  If the signature's designated requirement is only the identifier, it is treated as the same thing even when the contents change.
  The default requirement of an ad-hoc signature is the cdhash, which changes on every update.

## Steps

### 0. First check whether the permission is really needed

If you can avoid using the permission, that is the cheapest fix. `borders` (JankyBorders) called
`AXIsProcessTrusted()` at startup for a feature that was not in use, and macOS recorded a denied row for each store path.
It was fixed by removing the call with a patch, as in `modules/jankyborders.nix`.

See who requests the permission in the tccd log. `log` collides with a zsh builtin, so call it by absolute path.

```bash
/usr/bin/log show --last 1h --info --debug --style compact \
  --predicate 'process == "tccd" AND eventMessage CONTAINS "AttributionChain"' | grep -v apple | head
```

- `responsible_path` is what the permission attaches to, and `accessing` is the child process that actually requested it.
- The current permissions can be read from the system-side TCC database (if the terminal has Full Disk Access).

  ```bash
  sqlite3 -readonly "/Library/Application Support/com.apple.TCC/TCC.db" \
    "select service, client, client_type, auth_value, datetime(last_modified,'unixepoch','localtime') from access where service like 'kTCCService%' order by last_modified"
  ```

  `client_type` 1 means per path, and 0 means per bundle ID. If a per-path row is `/nix/store/...`, this procedure applies.
  User-domain permissions (Microphone, Automation, etc.) are in `~/Library/Application Support/com.apple.TCC/TCC.db`.

### 1. Choose the type

| Target | Type | Example |
|---|---|---|
| A single Mach-O (e.g. cava) | Put the binary in the .app and start it with `open` or launchd | `pkgs/cavaviz/default.nix` |
| Goes through a shell-script wrapper (e.g. the wrapper from `programs.*`) | Put only a small launcher in the .app and have it exec the wrapper | `pkgs/sketchybar-app/` |

When there is a wrapper, choose the launcher type. The type that copies the real binary into the .app must reproduce the PATH and LUA_PATH that the wrapper set up
with launchd's `EnvironmentVariables`. With the launcher type, the wrapper builds that environment as before.

### 2. Implement the launcher type

Copy `main.c` and `default.nix` from `pkgs/sketchybar-app/` to `pkgs/<tool>-app/` and rewrite these.

- In `default.nix`: `identifier` (`local.dotfiles.<tool>`), `name`, the .app name, the launcher's executable name, `CFBundleName`, `CFBundleExecutable`
- In `main.c`: the `perror` message

Leave these points in `default.nix` as they are. Removing them stops the permission from being kept.

- `dontFixup = true`: Darwin's fixup re-signs the Mach-O and overwrites the designated requirement.
- `/usr/bin/codesign --force --sign - -r='designated => identifier "${identifier}"' $app`: makes the requirement only the identifier.
  macOS's standard codesign can be called during the build thanks to `nix.settings.sandbox = false`. With the sandbox enabled, the build fails.
- `CFBundleIdentifier` and `CFBundleExecutable` in `Info.plist`: needed for attribution to the bundle ID. `LSUIElement` keeps it out of the Dock and menu bar.
- If the permission you need requires a TCC usage description, add a key such as `NSAudioCaptureUsageDescription`.

Pass only the wrapper's path as `target`. The signature's requirement is only the identifier, so the permission is kept even when the wrapper's store path changes on updates.

### 3. Swap the launchd agent

In `modules/<tool>.nix`, make launchd start the launcher instead of the wrapper directly. See `modules/sketchybar.nix` for an example.
`programs.*` sets `Program`, so `lib.mkForce` is needed.

```nix
let
  app = pkgs.callPackage ../pkgs/<tool>-app {
    target = lib.getExe config.programs.<tool>.finalPackage; # the existing wrapper
  };
in
{
  launchd.agents.<tool>.config.Program =
    lib.mkForce "${app}/Applications/<Tool>.app/Contents/MacOS/<tool>-launcher";
}
```

- home-manager converts `ProgramArguments` into `/bin/sh -c "wait4path && exec <Program>"`. `sh` is an Apple binary, so it does not become the responsible process, and the launcher does.
- Make the new files visible to the flake with `git add -N pkgs/<tool>-app`.

### 4. Build and verify

```bash
nix build --no-link '.#darwinConfigurations.ReinmuthLaptop.config.home-manager.users.reinmuth.home.activationPackage'
app=<the .app that was output>
codesign -d -r- $app                 # should show: designated => identifier "local.dotfiles.<tool>"
codesign --verify --strict $app
```

The user applies it with `nh darwin switch ~/dotfiles`. Claude does not run it. After switching, tell the user to confirm the following.

- With `/usr/bin/log show`, `responsible_path` is `<Tool>.app/Contents/MacOS/<tool>-launcher`.
- The prompt appears only the first time. Once allowed, it does not appear on later flake updates.

### 5. Cleanup (done by the user)

- Entries for the old `bash` or old store paths that remain in the permission list of System Settings can be removed manually with "−".
- `tccutil reset <Service>` clears the permission for the whole service, including other apps. Passing a bundle identifier clears only that app.

## Notes

- Changing the identifier makes the permission have to be granted again. Once decided, do not change the identifier.
- Unless the path changes, this procedure is unnecessary. An .app in `/Applications` or from a Homebrew cask is already handled by signature and bundle ID.
