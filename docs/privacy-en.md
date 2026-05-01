---
title: Privacy Policy & Terms
description: HLib (海阅) Privacy Policy and Terms · GB/T 35273-2020 compliant
permalink: /privacy-en/
lang: en
---

# Privacy Policy & Terms

> **Effective Date: May 1, 2026**  
> This statement is made in accordance with the *Personal Information Protection Law (PIPL)*, *Cybersecurity Law*, *Data Security Law* of the People's Republic of China, and the recommended national standard *GB/T 35273-2020 — Information security technology — Personal information security specification*.  
> [中文版](../privacy/) · [Home](../)

---

## 1. Overview

HLib (Chinese: 海阅) is an independent third-party reader client built on top of public Z-Library mirror APIs and is **not affiliated with Z-Library**. The app itself does not host or distribute any book content; all content comes from the mirror you choose.

This statement explains how we collect, use, store and protect your personal information, and the rights you have over your data. Please read it carefully, especially the clauses highlighted in **bold**.

---

## 2. Data Controller

This app is published and maintained by an independent developer.

- **App name**: HLib (Chinese: 海阅)
- **Developer type**: Independent individual developer
- **Contact**: [3185300855@qq.com](mailto:3185300855@qq.com)

For any questions related to this statement or to exercise your rights as a data subject, please contact us via the channel above.

---

## 3. Data Collection & Use

The app stores the following data only on your device and **never uploads them to the developer**:

### (a) Account information (sensitive, local only)

- Z-Library account cookies (`remix_userid` / `remix_userkey`) — encrypted via HarmonyOS HUKS hardware-backed key store, used solely to authenticate API requests to the mirror;
- Collected only when you actively log in or import via QR code; you may clear them at any time via Sign Out.

### (b) Business data (local only)

- Favorite book IDs and recent search keywords;
- Download tasks, download history, reading progress (filename, URL, timestamps only — **no book content**).

### (c) App preferences (local only)

- Theme, language, mirror selection, proxy & DoH settings, navigation style preference.

> **All network requests go directly to the Z-Library mirror you choose, with no intermediary server. This app integrates NO third-party analytics, ads, push, crash reporting or telemetry SDKs.**

---

## 4. Permissions

Permissions are requested following the principle of minimum necessity:

| Permission | Type | Purpose | Trigger |
|---|---|---|---|
| `ohos.permission.INTERNET` | Required | Access mirrors and download books | Granted at install time |
| `ohos.permission.GET_NETWORK_INFO` | Required | Check connectivity, show offline status | Granted at install time |
| Camera | Optional | Recognise QR codes for credential import; the captured image is used only for that single parse and is never saved or uploaded | When you tap "Scan QR Login" |
| Media R/W | Optional | Save books to the location you choose; the app does not read other files in that folder | When you pick a public Downloads folder |

You may revoke optional permissions any time via System Settings → Apps → HLib → Permissions.

---

## 5. Data Sharing

This app pledges:

- **NO sharing** of your personal information with any third party;
- **NO transfer** of your personal information to any third party;
- **NO public disclosure** of your personal information;
- **NO entrusted third-party processing**.

All your data is stored and processed only on your device. Interaction with mirror sites is limited to the queries/downloads you actively initiate; **no usage data is reported**.

---

## 6. Security Measures

We protect your data through:

- Sensitive credentials (account cookies) are encrypted via HarmonyOS HUKS (hardware key store) before being written to Preferences;
- All network requests use HTTPS by default (unless you manually configure an HTTP mirror or proxy);
- No information beyond business need is collected;
- Uninstalling the app causes the OS to wipe all local data — **nothing is left behind**.

Despite reasonable safeguards, please understand that the internet is not absolutely secure. Keep your device and account credentials safe.

---

## 7. Your Rights

Under PIPL and GB/T 35273 you have the following rights over your personal information:

- **Access & rectification**: all data is visible in Settings / Favorites / Download History and editable directly;
- **Deletion**: clear all local data via Settings → Clear cache; uninstalling removes everything;
- **Withdrawal of consent**: review this statement again from Settings → Privacy & Terms, or uninstall to withdraw consent;
- **Account deactivation**: this app does not create accounts on the developer side; deactivate your Z-Library account via the Z-Library website;
- **Decline personalisation**: this app performs no personalised push or automated decision-making.

---

## 8. Children's Privacy

This app is not specifically intended for children under 14 years of age. If you are a minor, please use the app under the guidance of your guardian and ask your guardian to read this statement with you.

If we become aware that we have collected personal information from a minor without guardian consent, we will delete the data as soon as possible.

---

## 9. Disclaimer

1. The app is only a mirror access tool; it does **not curate, cache or distribute any book content**;
2. You are responsible for ensuring your browsing/downloading/reading activity complies with copyright laws in your region;
3. Availability, legality of content and security of mirror sites are the responsibility of their respective operators, **not the developer of this app**;
4. The developer accepts no liability for inconvenience caused by mirror outages, legal risks or network issues;
5. The app is provided AS IS without express or implied warranty of fitness or stability.

---

## 10. Updates & Notice

We may update this statement to reflect changes in laws or features. Updated versions are released alongside app updates, and your consent will be requested again via the startup consent dialog after the effective date changes.

If you disagree with the updated content, you may stop using the app and uninstall it; continued use indicates acceptance of the updated statement.

---

## 11. Contact

If you have any questions, comments or suggestions about this statement, or wish to exercise your rights as a data subject, please contact us at [3185300855@qq.com](mailto:3185300855@qq.com). We will respond within **15 business days**.

---

© 2026 HLib (海阅) · This statement is identical to the *Settings → Privacy & Terms* shown inside the app.
