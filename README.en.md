<div align="center">

<img src="https://raw.githubusercontent.com/LZZLHY/hlib/master/docs/logo.svg" width="120" alt="HLib" />

# HLib （海阅）

**A third-party e-book reader for HarmonyOS**

Powered by public Z-Library mirrors · Search · Favorites · Read online · Download · Multi-mirror routing

<br/>

[![HarmonyOS](https://img.shields.io/badge/HarmonyOS-6.1.0%20(API%2024)-0E7C7B?style=flat-square&logo=harmonyos&logoColor=white)](#)
[![ArkTS](https://img.shields.io/badge/Language-ArkTS-2EC4B6?style=flat-square)](#)
[![ArkUI](https://img.shields.io/badge/UI-ArkUI-26A69A?style=flat-square)](#)

[![License](https://img.shields.io/badge/License-MIT-3F7DE0?style=flat-square)](LICENSE)
[![Version](https://img.shields.io/badge/version-1.0.1-FF9F1C?style=flat-square)](https://github.com/LZZLHY/hlib/releases)
[![Stars](https://img.shields.io/github/stars/LZZLHY/hlib?style=flat-square&color=FFBF69)](https://github.com/LZZLHY/hlib/stargazers)

[简体中文](README.md) · **English**

</div>

---

## Overview

HLib is a third-party e-book client for HarmonyOS. It provides book search, details, favorites, online reading and downloading through public Z-Library mirror APIs that the user selects.

The project itself does **not** store, cache or distribute any book content, and is **not** affiliated with Z-Library. Users are responsible for ensuring their use complies with the laws of their region.

## Features

- **Browse**: home recommendations / popular / recently uploaded, with content-language preference.
- **Advanced search**: keyword + language / order / format / publication-year filters, paginated.
- **Book details**: cover, author, metadata, description, similar books; favorite / read online / download.
- **Read online**: ArkWeb viewer with auto cookie injection, reading-position memory, font size & fullscreen.
- **Downloads**: streaming download, progress & status, history; open / share / auto mirror-fallback on failure.
- **Favorites & history**: local-first favorites with best-effort server sync; download history & reading progress persisted locally.
- **Multi-mirror**: built-in mirrors + concurrent latency test + custom domain + remote manifest sync + one-tap switch on Cloudflare block.
- **Privacy & security**: credentials encrypted with HUKS AES-256-GCM; local-first data; no third-party analytics / ads / push / crash reporting.
- **Responsive UI**: phone / foldable / tablet / large screen; bottom nav on small screens, side nav on large; light / dark / system; English & Simplified Chinese.

## Install

> ⚠️ Only an **unsigned HAP** (`entry-default-unsigned.hap`) is provided — there is **no app-store-signed package**. You must **sideload** it.

Download the latest `*-unsigned.hap` from [GitHub Releases](https://github.com/LZZLHY/hlib/releases), then either:

- **Self-sign (recommended)**: open the project in DevEco Studio, set your own debug signing under *Project Structure > Signing Configs*, then Build & Run to your device.
- **hdc sideload**: enable Developer Mode + USB debugging, run `hdc install path\to\entry-default-unsigned.hap` (the device must allow debug / unsigned apps).

Because it is not store-signed, tapping to install directly is usually blocked — use one of the sideload methods above.

## Build

```bash
ohpm install
set DEVECO_SDK_HOME=D:\Huawei\command-line-tools\sdk
hvigorw assembleHap --mode module -p product=default -p buildMode=debug
```

> **Signing**: the committed `build-profile.json5` ships an empty `signingConfigs` (no cert paths or passwords).
> Configure signing locally in DevEco Studio (*File > Project Structure > Signing Configs*); optionally run
> `git update-index --skip-worktree build-profile.json5` so local signing data is never committed.

## Architecture

```text
ArkUI Pages / Tabs / Components
        -> ViewModel (AuthVM / HomeVM / DownloadVM ...)
              -> ZLibraryClient -> HttpClient -> Z-Library mirror /eapi/*
                                       (CookieJar / CloudflareDetector / DomainFailover)
              -> Store layer -> AppStorage / PreferencesStore / HUKS SecretStore
```

See [README.md](README.md) (Chinese) for the full module breakdown.

## Disclaimer

1. This is a third-party client, not affiliated with Z-Library.
2. It does not store, distribute or moderate any book content.
3. All content comes from third-party mirror sites chosen by the user.
4. Users must ensure their use complies with local laws and regulations.
5. Mirror availability, content legality and safety are the responsibility of the respective sites.
6. Provided "as is", without warranty of any kind.

## License

[MIT License](LICENSE)

---

<div align="center">
© 2026 HLib · Made for HarmonyOS
</div>
