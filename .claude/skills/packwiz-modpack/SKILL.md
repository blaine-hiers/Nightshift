---
name: packwiz-modpack
description: Use when adding, removing, or updating mods/resource packs/configs in a packwiz Minecraft modpack (e.g. blaine-hiers/Blockworks), or when building a NeoForge mod against Modrinth Maven dev dependencies. Covers the loader/version pinning traps, side flags, shipped configs, rebase conflicts, and verification that every drain on Blockworks hit.
---

# packwiz modpack work

Gotchas that each cost a review round on Blockworks (MC 1.21.1, NeoForge). Check
every one; the reviewer will.

## Pin the right file
- **`packwiz mr add <slug>` can pick the wrong loader or MC version.** Multi-loader
  projects reuse one version-number string across Fabric/NeoForge/Forge and MC
  versions. After every add, confirm the `.pw.toml` file is the NeoForge build for the
  pack's MC version: `[update.modrinth] version` → `https://api.modrinth.com/v2/version/<id>`
  (`loaders`, `game_versions`), or download it and read `META-INF/neoforge.mods.toml`.
  Re-pin with `packwiz -y mr add --project-id <pid> --version-id <vid>`.
- **Modrinth Maven has the same collision**: `maven.modrinth:<slug>:<version_number>`
  silently resolves to whichever file was uploaded last. Pin dev deps by **version id**.
- **Modrinth's tags don't prove the jar loads.** Download every new jar and check
  `META-INF/neoforge.mods.toml` exists and has a `modLoader =` line. Structory Towers
  (every NeoForge 1.21.1 build) ships without one; NeoForge rejects the file, the
  whole mod state breaks, and the crash report blames an innocent mod (Sodium:
  "config could not be found"). Language providers (Kotlin for Forge) are exempt.
  The first `FATAL` in `logs/latest.log`, not the crash report, names the culprit.
- **`side = "server"` mods never reach singleplayer.** The client export omits them,
  and singleplayer's integrated server runs from the client install. Use `both` for
  anything that should work in singleplayer.
- Odd filenames are not proof of a mis-pin (Structory ships `…26.2_v1.3.7.jar` for
  1.3.17): trust the version id + mods.toml ranges.

## Sides
packwiz misreads Modrinth's `client_only_server_optional` / `server_only` and writes
`side = "both"`. Set `side` by hand from Modrinth `client_side`/`server_side`, then
sanity-check the jar: anything registering items/entities/blocks/payloads must be
`both`; renderers/ambience/resource packs `client`; data-only server mods `server`.

## Shipped configs (`defaultconfigs/`, `config/`)
- Get file names and keys from the mod's **source or bytecode**, never by guessing —
  a wrong key is silently ignored and the setting you shipped does nothing. NeoForge
  default name is `<modid>-<server|common|client>.toml` unless `registerConfig` passes
  one. Check value ranges: an out-of-range value is reset to default.
- Partial files are fine (missing keys are filled with defaults).
- `defaultconfigs/` only seeds **new worlds**; say so in the PR with the existing-world
  step (copy into `<world>/serverconfig/`).
- Default block-griefing settings are common (Superb Warfare, Create Big Cannons):
  for a shared server, check every new weapon/explosive mod for one.

## Plain files and resource packs
- Committed jars need a narrow `.gitignore` exception (`!mods/<name>-*.jar`) — the
  GitHub Java template ignores `*.jar`.
- `.packwizignore` keeps repo docs (README, LICENSE, .gitattributes) out of the pack.
- Resource packs are downloaded but **not enabled**; players toggle them in
  Options → Resource Packs, and pack order decides overlapping sounds. Document it.

## Parallel PRs and rebases
Every pack PR touches `index.toml` and `pack.toml`. Merge sequentially; on rebase,
take main's copy of both and regenerate: `git checkout --ours index.toml pack.toml &&
packwiz refresh && git add -A && git rebase --continue`, then confirm the index still
lists the branch's own files.

## Verify before claiming done
`packwiz refresh` → commit → `packwiz refresh` again leaves `git status` empty;
`packwiz curseforge export` and `packwiz modrinth export` both succeed and contain any
shipped configs/jars under `overrides/` (delete the exports — they're gitignored but
large). Read each new jar's `neoforge.mods.toml` for `type="incompatible"` and missing
required deps. In-game behaviour can't be tested here — list owner checks in the PR.
