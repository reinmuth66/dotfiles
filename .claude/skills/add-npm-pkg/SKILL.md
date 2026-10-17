---
name: add-npm-pkg
description: "Add an npm CLI missing from nixpkgs via importNpmLock (pkgs/<tool>/ lockfile, modules/<tool>.nix wrapper). Use whenever asked to install or Nix-manage an npm package, replace `npm install -g`, or add a node tool nixpkgs lacks, even if this skill is not named."
---

# Add an npm package to the Nix environment

Add an npm package that does not exist in nixpkgs to the nix-darwin environment with `importNpmLock`.
Do not use `npm install -g`, because it breaks reproducibility. Keep the lock file in the repository and let Nix build from it.

Arguments: `<tool> [version]`. If `version` is omitted, use the result of `nix shell nixpkgs#nodejs -c npm view <tool> version`.
The existing examples are `pkgs/czg/` and `modules/czg.nix`. When unsure, copy these two as a template and rewrite them.

Distinguish two kinds of names.
- `<tool>`: the official npm package name (e.g. `fkill-cli`). Use this official name as-is for `pkgs/<tool>/` and `modules/<tool>.nix`. A scoped package (`@scope/name`) cannot be used as a directory name, so use the `name` part.
- `<bin>`: the command name. It is a key of `bin` in `package.json` and can differ from the package name (the command of `fkill-cli` is `fkill`). Use it for the wrapper's name and the target it calls.

## Use npm only temporarily

`npm` is not on the PATH in this environment (Nix manages tools, so it is not installed globally).
Run every `npm` in the steps as `nix shell nixpkgs#nodejs -c npm ...`. Installing it permanently with `npm install -g` or `nix profile` breaks reproducibility.

## Steps

1. **Create package.json.** Name it `<tool>-nix` so it does not collide with anything. Set `private: true` and put the target in `dependencies`.
   If the CLI loads extra plugins or peer dependencies at runtime, list them in `dependencies` too (`pkgs/czg/package.json` lists `czg` and `cz-git`).
   Also look up the command name `<bin>` with `nix shell nixpkgs#nodejs -c npm view <tool> bin` (used in steps 3 and 6).

   ```bash
   mkdir -p pkgs/<tool>
   cat > pkgs/<tool>/package.json <<EOF
   {
     "name": "<tool>-nix",
     "version": "1.0.0",
     "private": true,
     "dependencies": {
       "<tool>": "<the version you checked>"
     }
   }
   EOF
   ```

2. **Create package-lock.json.** `importNpmLock` builds from the hashes in the lock file, so the lock file is required.
   `--package-lock-only` avoids creating node_modules.

   ```bash
   cd pkgs/<tool> && nix shell nixpkgs#nodejs -c npm install --package-lock-only
   ```

3. **Create modules/<tool>.nix.** The wrapper calls the output of `buildNodeModules`.
   `NODE_PATH` is set so that the CLI can resolve its dependencies with `require`.

   ```nix
   { pkgs, ... }:
   let
     nodeModules = pkgs.importNpmLock.buildNodeModules {
       npmRoot = ../pkgs/<tool>;
       nodejs = pkgs.nodejs;
     };
     <bin> = pkgs.writeShellScriptBin "<bin>" ''
       export NODE_PATH="${nodeModules}/node_modules"
       exec ${pkgs.nodejs}/bin/node ${nodeModules}/node_modules/.bin/<bin> "$@"
     '';
   in
   {
     home.packages = [ <bin> ];
   }
   ```

   Even when `<bin>` differs from `<tool>`, the wrapper's name and the `.bin/` target are `<bin>`. If you leave them as `<tool>`, the build still passes but the command fails at runtime with `No such file or directory`.

4. **Add `./<tool>.nix` to the imports of modules/home.nix.**

5. **Make the files visible to the flake.** A flake reads only files that git tracks. Mark new files as intent-to-add.

   ```bash
   git add -N pkgs/<tool> modules/<tool>.nix
   ```

6. **Build, then actually run the command.** A passing build misses these two failures:
   - If you forget to add the module to the imports of `home.nix`, the build still passes.
   - If the wrapper calls the wrong bin name, the build still passes. The wrapper is a shell script, so its content is not verified until it runs.

   So build the whole system first, then build `home.path` (what goes into the user's environment) and run the command.

   ```bash
   nix build --no-link .#darwinConfigurations.ReinmuthLaptop.system
   out=$(nix build --no-link --print-out-paths '.#darwinConfigurations.ReinmuthLaptop.config.home-manager.users.reinmuth.home.path')
   $out/bin/<bin> --version
   ```

   For a tool without `--version`, use a side-effect-free argument such as `--help`.
   Some tools print nothing for either (`kill-port` exits silently for both `--version` and `--help`). With no output you cannot tell whether it worked.
   In that case, pass a harmless argument and check the tool's own output (for `kill-port`, pass an unused port number and it prints `No process running on port`).
   If `No such file or directory` appears, fix the bin name or the wrapper. Checking only that the file exists with `ls $out/bin/` is not enough (a wrapper with the wrong bin name exists too).

## Applying to the machine

The user runs `nh darwin switch ~/dotfiles`. Claude does not run it. Commit only when the user asks.
Tell the user to confirm startup after switching with a side-effect-free command such as `<bin> --version`.

## Updating

To bump the version, rewrite `pkgs/<tool>/package.json` and redo the lock generation in step 2 and the build check in step 6.
