---
name: add-auto-update-tool
description: "Add a tool or source missing from nixpkgs, pinned, with an auto-update PR workflow: release binary (fetchurl), tag-pinned flake input, or flake = false input. Use for pinning versions or revs, update-*.yaml workflows, or replacing fetchFromGitHub rev pins, even if this skill is not named."
---

# Add a tool or source pinned, with an auto-update PR

Add a tool or source that is not in nixpkgs, pinned, so that a PR is created weekly when a new release or commit appears.
Not needed for tools in nixpkgs (the weekly `update-flake.yaml` updates them together with nixpkgs).

Arguments: `<owner/repo> [tool-name]`.

## Why automation is needed

A flake has no mechanism to "follow the latest release tag". All `nix flake update` does is re-resolve the commit that the specified ref (a branch or tag) points to.

- To pin to a tag, you need a separate mechanism that rewrites the tag string itself (the workflows of methods A and B).
- To follow the latest commit of a branch, it is enough to make it a `flake = false` input with no ref. `nix flake update` in `update-flake.yaml` updates the rev and hash (method C).

What is automated ends at creating the PR. Applying to the machine happens after the PR is merged, when the user runs `nh darwin switch`.

## Choosing a method

It depends on the shape of the upstream and what you want to follow. Check from the top and use the first one that applies.

| Condition | Method | Follows | Existing example |
|---|---|---|---|
| A built artifact (e.g. `.app.tar.gz`) is attached to the release | A: release binary (`fetchurl`) | Latest Release | `nix/zmk-battery-center.nix`, `update-zmk-battery-center.yaml` |
| There is a `flake.nix` at that tag and it outputs `packages.<system>.<name>` | B: tag-pinned flake input | Latest Release | `modules/mole.nix`, `update-mole.yaml` |
| None of the above (no Release, no artifact, no flake, you build it yourself, you patch it) | C: follow the source with a `flake = false` input | Latest commit of the default branch | `catppuccin-bat`, `zeno-zsh`, `pdf-cli` (`flake.nix`) |

- When both A and B apply, A is lighter because it needs no build. B, however, has the advantage that upstream maintains things like `vendorHash`.
- C takes in the **latest commit of the branch**, not a Release. Unreleased changes come in too, so choose A or B if you need stability.
- Derived hashes in C (e.g. Go's `vendorHash`) cannot be followed by a flake input. See the section "Derived hashes in C".
- Anything you want to stop at an old commit on purpose (e.g. `nixpkgs-spotify`) is not a target of auto-update. Manage it by hand, leaving the rev in the URL.

### Prerequisites for B (easy to forget)

- Check whether the flake exists at the tag. The flake may exist only on main and not at the tag (Mole added Nix support around V1.59.0, so earlier tags have no `flake.nix`).

  ```bash
  gh api "repos/<owner>/<repo>/contents/flake.nix?ref=<tag>" --jq .name
  ```

- Even if upstream splits out `package.nix` into a separate file, the consumer side and the workflow need no change as long as the flake's output (`packages.<system>.<name>`) is the same.
- With `inputs.<name>.inputs.nixpkgs.follows = "nixpkgs"`, it is built with your nixpkgs and flake.lock does not bloat. If a builder that upstream requires (e.g. `buildGo126Module`) is missing in your nixpkgs, the build fails. In that case, remove `follows`.
- `gh release view` returns the release designated as "Latest". Even for a repository with several tag lines (such as Mole's `V1.34.0-windows`), confirm with `gh release list` that Latest points to the correct line.
- A and B detect updates with `gh release view`, so they cannot be used for an upstream that has no Release (including a tags-only repository). Use C in that case.

## Procedure A: release binary

1. Create `nix/<tool>.nix` using the existing `nix/zmk-battery-center.nix` as a template (`stdenvNoCC.mkDerivation` + `fetchurl`, with `version` and `hash` in one place each).
2. In `modules/<tool>.nix`, call `pkgs.callPackage ../nix/<tool>.nix { }` and add it to `home.packages`. Add it to the `imports` of `modules/home.nix`.
3. Copy `.github/workflows/update-<tool>.yaml` from `update-zmk-battery-center.yaml` and change these.
   - The repository in `gh release view --repo`
   - The file that the `grep` reading the current version targets
   - The artifact `URL` (the asset name template)
   - The target file of `sed`, the PR branch name, and the title
4. Watch the tag prefix. zmk strips the `v` of `v0.13.0` before putting it in `version`, and restores it as `v${VERSION}` in the URL. Adjust to the upstream's tag format.
5. `sed -i "s/version = .../"` replaces every match in the file. If a file has several `version =`, narrow the target.

## Procedure B: tag-pinned flake input

1. Add it to `inputs` in `flake.nix`. Set the tag to the current latest release.

   ```nix
   <name> = {
     url = "github:<owner>/<repo>/<tag>";
     inputs.nixpkgs.follows = "nixpkgs";
   };
   ```

2. Add `<name>` to `inherit (inputs) ...` in `home-manager.extraSpecialArgs` of `outputs`.
3. Create `modules/<tool>.nix` and add it to the `imports` of `home.nix`.

   ```nix
   { <name>, pkgs, ... }:
   {
     home.packages = [ <name>.packages.${pkgs.stdenv.hostPlatform.system}.<name> ];
   }
   ```

   Use `packages.<system>` and do not rely on `overlays.default`. The overlay may not exist in the flake at that tag.

4. Copy `.github/workflows/update-<tool>.yaml` from `update-mole.yaml` and change these.
   - The repository in `gh release view --repo`
   - The URL part of `grep -oP` and `sed` (`github:<owner>/<repo>/` and the tag regex)
   - The input name in `nix flake update <name>`
   - The branch name and the commit/title wording
5. If the tag can contain something other than digits and dots (`-beta`, `-rc1`, etc.), widen the regex `V[0-9.]+`.

## Procedure C: follow the source with a `flake = false` input

Replace what you had pinned with `pkgs.fetchFromGitHub { rev, hash }` by a flake input. No new workflow is needed. `update-flake.yaml` runs `nix flake update` every week and updates the rev and hash in `flake.lock`.

1. Add it to `inputs` in `flake.nix`. Do not give a ref (giving one pins it to that ref).

   ```nix
   <name> = {
     url = "github:<owner>/<repo>";
     flake = false;
   };
   ```

2. Add `<name>` to `inherit (inputs) ...` in `home-manager.extraSpecialArgs` of `outputs`.
3. On the consumer side, replace `fetchFromGitHub` with the input.

   - For a module, add `<name>` to the arguments and write `src = <name>;` (examples: `modules/bat.nix`, `modules/zeno.nix`)
   - For a package that you `callPackage`, pass it as an argument (such as `src`) (example: `modules/pdf-cli.nix`)
   - `${<name>}` becomes a store path. `<name>.rev`, `<name>.shortRev`, and `<name>.lastModifiedDate` are also usable (for composing the version, etc. Example: `nix/pdf-cli.nix`)

4. When migrating from an existing pinned commit, lock it at the same commit. If you do nothing, it advances to the latest commit at lock time.

   1. First add `/<current rev>` to the URL and run `nix flake lock`. If the locked `narHash` matches the hash of the original `fetchFromGitHub`, the source is identical.
   2. Remove the rev from the URL.
   3. Delete `original.rev` from the corresponding node of `flake.lock`.

      ```bash
      jq 'del(.nodes["<name>"].original.rev)' flake.lock > flake.lock.new && mv flake.lock.new flake.lock
      ```

   4. Run `nix flake lock` and confirm that `flake.lock` shows no diff (the rev does not move).

   `--override-input` is not written to `flake.lock`, so it cannot be used for this purpose.

### Derived hashes in C (vendorHash etc.)

Hashes derived from the source (Go's `vendorHash`, npm's `npmDepsHash`, Rust's `cargoHash`) depend on `go.sum` and the like, so a flake input cannot follow them. Once the source is C, add a step that recomputes the hash after `nix flake update` in `update-flake.yaml`. See `Update pdf-cli vendorHash` in `update-flake.yaml` for an example.

1. Replace the hash with a dummy (`sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=`) using `sed`.
2. Build only the intermediate derivation that holds the hash, not the whole package. For Go it is `.goModules`. Pass the input from `builtins.getFlake (toString ./.)` with `nix build --impure --expr`. Use `system = builtins.currentSystem` so it also works on an ubuntu runner.
3. Take the correct hash from the `got:` line of the failure output and write it back with `sed`.
4. If it could not be obtained, restore with `git checkout` and do not stop PR creation, using `continue-on-error: true`.

Notes:

- `run:` in GitHub Actions runs with `bash -eo pipefail`. `HASH=$(grep ... | head -1)` exits before reaching the if when nothing matches, unless you add `|| true`.
- Attrs other than `.goModules` (such as `npmDeps`) are unverified in this environment. Confirm locally that the same procedure works before using them.
- The same-commit migration in step 4 lets you confirm that the recomputed hash matches the original hash (confirmed to match for `pdf-cli`).

## Common finishing steps

- Copy from an existing workflow. Match the action versions (`checkout`, `nix-installer-action`, `create-pull-request`) to the existing `update-*.yaml`.
- **Add failure notification.** A missing PR cannot distinguish "no update" from "failure". Put the following step at the end of the job and add `issues: write` to `permissions`.
  While the same failure continues, comments are appended to the open Issue, and a recurrence after you fix and close it becomes a new Issue.

  ```yaml
  - name: Report failure
    if: failure()
    uses: ./.github/actions/notify-failure
    with:
      key: 'failure:<workflow name>'
  ```

  A step with `continue-on-error: true` is not caught by `failure()`. Give that step an `id` and notify with `if: steps.<id>.outcome == 'failure'` (example: `vendorhash` in `update-flake.yaml`).
- **Do not let it idle silently.** In the steps that fetch the current version and the latest version, validate the format with a regex and `exit 1` if unexpected. At the end of the rewriting step, confirm that a diff appeared.
  If you put `git diff --quiet X && { ...; exit 1; }` on the last line, it returns exit code 1 in the normal case where there is a diff. Write `if git diff --quiet X; then ...; exit 1; fi` instead.
- If the logic is complex, do not write it directly in the workflow. Extract it to `scripts/`, put mock `gh` / `nix` on the PATH, and verify every branch with `DRY_RUN=1` (example: `scripts/spotify-update-check.sh`).
- Add to the lock with `nix flake lock` (other inputs do not move). Make new files visible to the flake with `git add -N` before evaluating. Untracked files are invisible to the flake.
- It does not conflict with the weekly `update-flake.yaml`. Tag-pinned inputs of A and B stay at the same tag even when `nix flake update` runs. Inputs of C are updated by `update-flake.yaml`.
- Commit only when the user asks. The user also runs `nh darwin switch`.

## Verification

Before applying to the machine, check in this order.

1. Build on its own (for B)

   ```bash
   nix build --impure --no-link --print-out-paths --expr \
     'let f = builtins.getFlake (toString ./.); in f.inputs.<name>.packages.aarch64-darwin.<name>'
   ```

2. Evaluate the whole

   ```bash
   nix eval --raw .#darwinConfigurations.ReinmuthLaptop.system.drvPath
   ```

   When you replaced `fetchFromGitHub` in C, build the whole instead of only evaluating. A package that you patch, or one that uses macOS's standard toolchain (such as `/usr/bin/swiftc`), can pass evaluation yet have failures that only show at build time.

   ```bash
   nix build --no-link --print-out-paths .#darwinConfigurations.ReinmuthLaptop.system
   ```

3. Smoke-test the artifact. Run only side-effect-free commands (such as `--version`).
4. To check the workflow's behavior, run `workflow_dispatch` on GitHub's Actions page after pushing. To create a PR, "Allow GitHub Actions to create pull requests" must be enabled in the repository settings (it is, if the existing workflows work).
5. While the current version matches the latest, the workflow itself ends with "no update". To try the update path, run it with the tag in `flake.nix` (or `nix/<tool>.nix`) set back by one. For C, no diff appears while the rev in `flake.lock` matches the latest.

## Known limitations

- The automatic PR does not verify the build (an ubuntu runner cannot build for Darwin). A broken update is found only by the `nh darwin switch` build after merging. If needed, add a job that runs `nix build` on a `macos-latest` runner.
- C follows the latest commit, so a breaking change upstream becomes a PR as it is. `update-flake.yaml` puts all inputs into one PR, so when one breaks, the other updates are dragged along. To stop only the broken input, pin it by adding `/<rev>` to the URL and revert that part of `flake.lock` in the PR.
- An input in C does not fetch submodules (neither does `fetchFromGitHub`). If you need submodules, use a `git+https://...?submodules=1` URL.
- If the tool has its own update feature (such as `mo update`), confirm that it is disabled under Nix management.
