# Tizen Optimization

A personal case study in making a Samsung Tizen TV quieter and more useful
as an HDMI display — **adapted from [Quiet Tizen](https://github.com/jss8649/quiet-tizen)**,
which documented a different Samsung TV model. This repository reproduces
that work on a **2023 Samsung UN58CU7700GXZD**, a smaller/older TV with a
different firmware, app catalog and launcher host than the one Quiet Tizen
was originally built against. Most of the original toolkit's assumptions
did not carry over unchanged; this README documents exactly what did, what
didn't, and what had to be adapted or fixed along the way.

It includes **Quiet Home**, the same native .NET/NUI launcher from the
original project, now installed as this TV's actual Home/startup app, plus
a cleanup profile, generalized access/build tooling and rollback recipes
specific to this device.

**This is a working case study, not a universal installer.** If you try
this on another TV — even the "same" model in another size or region — read
[AGENTS.md](AGENTS.md) and start with your own inventory. A matching brand,
year, Tizen version or successful root check is not enough on its own.

## Give this repository to your coding agent

Clone the repository, open it in your coding agent, and use:

> Read README.md and AGENTS.md, then inspect the documentation before touching
> my TV. Help me reproduce this on a TV I own. First identify its exact
> model, firmware and runtime, compare them with the profiles already
> recorded here, and show me any compatibility gaps. Keep HDMI, sound,
> networking, Bluetooth and accessibility working. Prefer HDMI and minimize
> smart features; keep the streaming apps I choose. Back up my actual
> settings and prepare rollback before each change. Install and verify Quiet
> Home before assigning it to Home/startup. Use the measured findings and
> known limitations rather than assuming every package is spyware or
> promising a particular speed improvement.

## Tested devices

| Item | Original (Quiet Tizen) | This repository |
|---|---|---|
| Model | `UN75U8000FFXZA` (2025, 75") | `UN58CU7700GXZD` (2023, 58") |
| Firmware | `T-KSU2EFAKUC-0090-1300.9` | `T-KSU2ECUABC-0090-2230.0` (confirmed the latest version Samsung publishes for this model) |
| Platform | Tizen 9.0, Linux 5.4.261, ARMv7, .NET 6.0.9 | Linux 5.4.77, ARMv7, .NET 6.0.9 |
| Launcher host | `com.samsung.tv.bixby-promotion` (a dormant Bixby onboarding placeholder) | Does not exist on this TV. Uses `com.samsung.tv.AccountNudgeService` instead (see below) |
| Wi-Fi | — | MediaTek MT7668 USB combo chip, driver `mt7668u-MTK.v5.1.0` |

See [profiles/un58cu7700gxzd-2230.0.json](profiles/un58cu7700gxzd-2230.0.json)
for the full recorded inventory, cleanup groups, stop-markers, preferences
and launcher notes for this exact device.

## What changed from the original project

### Toolkit bugs, not TV-specific

These were found while running the original toolkit on Windows and affect
anyone doing the same, regardless of TV model:

- **`tools/tv.py` never decoded its own base64 payload.** `--script` piped
  base64 text straight into `/bin/sh` without a `base64 -d` step. On the
  first attempt this just failed ("command not found"); depending on the
  script's exact byte content it could also silently parse as a harmless
  shell variable assignment and do nothing at all, with no error. Fixed to
  decode before piping to `/bin/sh -s`.
- **`core.autocrlf=true` on Windows corrupts the recipes.** Git checked the
  `recipes/*.sh` files out with CRLF line endings, which the TV's `/bin/sh`
  chokes on. Added [.gitattributes](.gitattributes) forcing LF for `*.sh`,
  and the same fix in `tools/plan_cleanup.py` and
  `vendor/samsung_tv_root/sdb.py`, which both generate shell scripts at
  runtime and need to write them with explicit `\n` line endings.
- `find ... -exec cmd {} \;` run through `tv.py exec --command` loses the
  trailing `\;` somewhere in the Windows → WSL-less shell → C# `/bin/sh -c`
  chain. Use `-exec cmd {} +` instead when working this way, or put the
  command in a `--script` file instead (which doesn't go through the same
  quoting layer).

### Inventory and cleanup

A fresh inventory of this TV found 43 of the original profile's 54 app IDs
present, in the same default state. The gaps were real, not errors: 6 newer
`AICompanion`/`ai-discovery` app IDs from the 2025 TV don't exist on this
2023 one, and a vendor-hashed promotion package id doesn't either. This TV
also had 2 extra ad/ACR apps the original profile didn't know about
(`com.samsung.tv.coba.adagent`, `com.samsung.tv.iacr`), added as their own
cleanup phase. All 10 of the original's `stop_markers` matched this TV's
systemd units byte-for-byte (checked with `systemctl cat`, not assumed).

Applied and verified on this TV, each with its own snapshot and restore
script: the `advertising`, `advertising-extra`, `voice`, `context` and
`smart-extras` registry groups (42 apps total), all 10 stop-markers, the 6
`vconftool` preferences, the WAS cache field, and the 4 runtime-only systemd
masks. `tv-plus` was applied and then **deliberately restored** after the
owner said they use Samsung TV Plus regularly — it now has its own catalog
shortcut in Quiet Home instead.

### The launcher needed a different host, and more code changes than expected

The original technique repurposes one dormant native app's package instead
of installing a new one, so that Samsung's package-signature trust carries
over to the launcher without needing a proper developer certificate
accepted as Home. On this TV, `com.samsung.tv.bixby-promotion` simply
doesn't exist. The search for a replacement took two passes:

1. Searching `app_type='dotnet'` found only 3 candidates, and all three
   turned out to be AirPlay/Apple TV stub apps with **zero** references to
   `dotnet`/`hostfxr`/`libcoreclr`/`NUI` in their binaries despite the
   `dotnet` tag — native code mislabeled, not usable.
2. Broadening to `app_type LIKE '%dotnet%'` (this TV mostly uses
   `dotnet-inhouse`, not plain `dotnet`) found about 130 real candidates.
   `com.samsung.tv.AccountNudgeService` — a dormant Samsung Account sign-in
   promo — was chosen: closest in spirit to the original Bixby Promotion
   placeholder, and its manifest declares no OS-level auto-launch
   `app-control`. `com.samsung.tv.csfs`, the TV's real Home/FirstScreen
   shell (537 KB, AOT-compiled, 28+ privileges including Bluetooth and
   settings admin, watchdog-supervised), was deliberately left untouched —
   too deeply integrated to safely repurpose.

Repurposing a different host exposed assumptions baked into the original
code that a single-TV case study had no reason to question:

- `launcher/src/Home.cs` had the app's own resource path **hardcoded** to
  `/opt/usr/apps/com.samsung.tv.bixby-promotion/...`. It now resolves this
  at `OnCreate()` from `Application.Current.DirectoryInfo.Resource`, so one
  build works under any host app_id.
- `tools/build.py` and `Home.csproj` hardcoded the output assembly name to
  `BixbyPromotion`. It's now an MSBuild property
  (`-p:LauncherAssemblyName=...` / `--launcher-assembly-name`), defaulting
  to the original value.
- `recipes/install-launcher.sh` / `restore-launcher.sh` hardcoded the host
  app_id and dll filename throughout. Both now take them as explicit
  arguments.
- The host's own `runtimeconfig.json` declared `netcoreapp2.0`, not
  `net6.0` — the original `BixbyPromotion.dll` apparently already matched
  `net6.0`, so the original recipe never needed to touch that file. This
  one does: it now deploys and backs up a matching `runtimeconfig.json`
  alongside the `.dll`, not just the `.dll` alone.
- HDMI source IDs are wiring, not a protocol: this TV's `13`/`14` map to
  "HDMI1"/"HDMI2" (the owner's PS5 and Switch, respectively), and `15` here
  is the soundbar's ARC return channel, not a third HDMI input — `get_source_list()`
  never reported one, because there isn't one on this TV. The example
  third HDMI card from the original layout was removed instead of guessed.

The settings-bridge app (`launcher/src/QuickLaunch.cs`) still hardcodes
`com.samsung.tv.bixby-promotion` as its launch target. It hasn't been
attempted on this TV yet, so that fix is still pending.

### Catalog and artwork

Official artwork was fetched for the apps actually installed on this TV —
Netflix, YouTube, Prime Video, HBO Max, Disney+, Spotify, Apple TV, Xbox
(already sourced in the original `artwork-sources.json`), plus newly sourced
entries for **Moonlight** (official icon from the `moonlight-stream/moonlight-qt`
GitHub repo, GPLv3), **Crunchyroll**, **Globoplay**, **Stremio** and
**Samsung TV Plus** (official App Store / Play Store publisher artwork).
Hulu, Tubi and Amazon Luna were removed from the catalog — they simply
aren't installed on this TV, and a shortcut to an app that isn't there is
worse than no shortcut.

`feature-ps5.svg` and `free-dock-ps5.svg` replace the original's generic
illustrated controller/wordmark cards with Sony's actual PlayStation 5
logo and wordmark, recolored white. Unlike the other publisher marks (which
stay as local, gitignored downloads), this one is small enough and
Wikimedia-tagged public domain that it's tracked directly in the repo — see
[NOTICE.md](NOTICE.md) for the exact source and why.

### Home/startup

Visibly verified first — manual launch, HDMI switching against the owner's
actual PS5/Switch wiring, artwork loading without error, a full reboot with
the registry/stop-marker/preference changes surviving it — then
`db/appfw/home_appid`, `db/appfw/startup_appid` and the main-operation
handler were all pointed at `com.samsung.tv.AccountNudgeService`. The TV now
boots directly into Quiet Home. The three original values
(`com.samsung.tv.csfs` for all three) are recorded in this TV's `home-01`
backup for `restore-launcher.sh`.

`db/menu/autorun_tv_plus` was deliberately left **off**: that preference
makes Samsung TV Plus hijack the boot/wake sequence ahead of whatever is set
as Home, which would undo the whole point of setting Quiet Home as Home.
TV Plus still works fine as a manual shortcut; it just never auto-launches.

## Measured state (not a before/after number)

No memory/process baseline was captured before cleanup started, so there is
**no honest percentage to report** for how much faster or lighter this made
the TV — see [docs/07-performance.md](docs/07-performance.md) for why this
project avoids that kind of unverified claim. What was actually measured, as
a snapshot after everything below was applied:

| | |
|---|---|
| Background services confirmed no longer auto-running | 13 (9 stopped via stop-markers, 4 masked for the current boot) |
| `MemAvailable` | ~380 MB of 1.6 GB total |
| Running processes | 236 |
| Running systemd service units | 126 |

Getting a real before/after delta would mean restoring everything, rebooting,
measuring, then reapplying and rebooting again — two full TV restarts purely
for the benchmark. Full numbers and the exact services are in
[profiles/un58cu7700gxzd-2230.0.json](profiles/un58cu7700gxzd-2230.0.json)'s
`measured_state`.

## What hasn't been done yet

- **Settings bridge** (`docs/04-launcher.md`'s `QuickLaunch` remap of the
  "More"/settings key). Not attempted on this TV; `QuickLaunch.cs` still
  needs the same hardcoded-app_id fix `Home.cs` got.
- **`light-shell`** cleanup group (native sidebar/browser). Documented as
  depending on the settings bridge being done first; left alone until then.
- The 4 runtime-only systemd masks (`ipa`, `contents-recognition-service`,
  `sp-kpi`, `data-service`) do **not** survive a reboot by design — their
  unit definitions aren't writable on this firmware. Re-apply them after
  any restart if you want them masked again; nothing breaks if you don't.

## What is here

| Component | What it does |
|---|---|
| [Quiet Home source](launcher/src/Home.cs) | Native .NET/NUI home, HDMI cards, app library and quick settings |
| [App catalog](launcher/assets/apps.json) | Public text-placeholder catalog; see `apps.local.json` (gitignored) for this TV's real one |
| [Artwork sources](launcher/artwork-sources.json) | Per-app official artwork sources and licensing notes |
| [This TV's profile](profiles/un58cu7700gxzd-2230.0.json) | Full inventory, cleanup groups, stop-markers, preferences and launcher notes |
| [Original U8000F profile](profiles/un75u8000ffxza-1300.9.json) | Kept for reference; not this TV |
| [Cleanup planner](tools/plan_cleanup.py) | Field-specific apply/restore SQL generated from your own fresh snapshot |
| [Access helper](tools/tv.py) | Explicit-target SDB preflight, temporary authenticated root, bounded transfers, per-TV `--profile` |
| [Recipes](recipes) | Snapshot, stop-marker, launcher, settings-bridge and restoration scripts |
| [Evidence](evidence/observations.json) | Sanitized observations from the original device; see the profile above for this one |

## Walkthrough

These largely follow the original project's phases; read each doc for the
generic mechanics, and this TV's profile/README sections above for what
actually differed in practice.

1. [Understand compatibility and inventory the TV](docs/01-inventory.md).
2. [Enable Developer Mode and check temporary access](docs/02-access.md).
3. [Take snapshots and apply selected cleanup](docs/03-cleanup.md).
4. [Build, install and assign Quiet Home](docs/04-launcher.md) — read the
   "launcher needed a different host" section above first if your TV also
   lacks `com.samsung.tv.bixby-promotion`.
5. [Pair a DualSense using the TV's Bluetooth support](docs/05-controller.md).
6. [Customize apps, fetch artwork and keep it preloaded](docs/06-artwork.md).
7. [Diagnose slow streaming apps without overclaiming](docs/07-performance.md).
8. [Understand privacy findings](docs/08-privacy.md).
9. [Restore the original experience](docs/09-recovery.md).

Read [AGENTS.md](AGENTS.md) before using the tools. TV commands require a
specific address, a verified firmware declaration, and (now) a `--profile`
naming which TV you mean. All downloaded proprietary references, local
artwork, snapshots and session records stay under ignored paths.

## Models that might work the same way, or with adjustments

**Not verified — read this as "worth trying your own inventory on," not
"confirmed compatible."** The project's own rule still applies: a matching
model name or year is not enough on its own.

`UN58CU7700GXZD` is a regional name for Samsung's 2023 entry-level Crystal
UHD line, sold under different names depending on country: `CU7000` (US),
`CU7100`/`CU7110` (UK), `CU7179` (Germany), `CU7105` (France), `CU7170`
(Italy), `CU7700` (this TV's region). These are reported to be the same
underlying hardware/software platform re-badged per market, so in rough
order of how much I'd trust them without checking:

- **Other screen sizes of the same `CU7700` line** (same region/retail
  naming — 43", 50", 55", 65", 70", 75", 85"): most likely to share this
  exact firmware family and app catalog. Still run your own inventory —
  don't assume the exact firmware string or every app ID matches.
- **The same generation under another region's name** (`CU7000`, `CU7100`,
  `CU7110`, `CU7179`, `CU7105`, `CU7170`, and their own size variants):
  likely the same Tizen platform and launcher-repurposing approach, but
  expect a different firmware version string and a different regional app
  catalog (this TV's Globoplay/Crunchyroll shortcuts are very Brazil/LatAm
  specific, for instance). The dormant-app search in "launcher needed a
  different host" above is the part most likely to need redoing per region.
- **The step-up 2023 line (`CU8000`/`CU8500`)**: same TV generation, higher
  hardware tier. Plausible the same approach applies, but unverified —
  treat it as its own case study until someone actually runs the inventory.
- **Anything outside 2023's entry Crystal UHD generation** (older/newer
  years, QLED/Neo QLED lines, other regions' naming I haven't checked): no
  basis to guess either way. Start from `docs/01-inventory.md` as if this
  repository didn't exist for your model, the same way this repository
  started from the original Quiet Tizen one.

## Development

Host tools use Python 3.12+ and the standard library. Raster artwork conversion
optionally uses Pillow. Source builds use the .NET 6 SDK to match the tested
TV; it is an older SDK and should be isolated from unrelated projects.
Tizen's SDB now ships through the Tizen VS Code extension rather than the
retired Tizen Studio — see [docs/02-access.md](docs/02-access.md).

```sh
python3 -m unittest discover -s tests -v
python3 tools/build.py payloads
# After obtaining the four private Tizen reference assemblies from your TV:
python3 tools/build.py launcher --framework .local/tv-framework \
  --launcher-assembly-name com.samsung.tv.AccountNudgeService
```

## Credits

This repository adapts [Quiet Tizen](https://github.com/jss8649/quiet-tizen)
by jss8649, which in turn adapts the visual design of
[Free My TV](https://github.com/simbasjungles/free-my-tv) and vendors the
temporary archive-launcher access route from
[samsung-tv-root](https://github.com/chris-ritsen/samsung-tv-root). This is
a native Tizen port of the visual approach, not an installation of the
Android launcher. See [NOTICE.md](NOTICE.md) and
[docs/provenance.md](docs/provenance.md) for exact commits, licenses and
the changes made on top for this TV.

Original project code is MIT-licensed. Third-party fonts, symbols, access
code and the tracked PlayStation 5 logo retain their own licenses/terms. No
Samsung firmware, stock app binaries, private TV backups or (gitignored)
publisher app artwork is included in this repository.
