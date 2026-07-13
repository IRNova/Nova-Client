<div align="center">

# Nova

### Fast, free, and unrestricted internet, built for Iran.

[![Latest release](https://img.shields.io/github/v/release/iiviirv/Nova-Client?label=latest&color=7c5cff)](https://github.com/iiviirv/Nova-Client/releases/latest)
[![Downloads](https://img.shields.io/github/downloads/iiviirv/Nova-Client/total?color=22c55e)](https://github.com/iiviirv/Nova-Client/releases)
[![Platform](https://img.shields.io/badge/platform-iOS%20%C2%B7%20Android%20%C2%B7%20macOS%20%C2%B7%20Windows-3ddc84)](https://github.com/iiviirv/Nova-Client/releases/latest)
[![License](https://img.shields.io/badge/license-GPL--3.0-blue)](https://github.com/SagerNet/sing-box/blob/main/LICENSE)

**[⬇️ Download the latest version](https://github.com/iiviirv/Nova-Client/releases/latest)**

</div>

---

## What is Nova

Nova is a lightweight, modern VPN client for **iPhone, Android, macOS and Windows**. Tap the logo to connect, and you get a clean dashboard that shows your country, public IP, ping, and live download and upload speed. It works with the subscription you already have, and it can build and manage your own private server for you, all from inside the app.

Nova is designed for difficult networks. It bundles the anti-censorship tools people in Iran actually need (TLS fragmenting, WARP, secure DNS, Iran direct-routing) behind a simple, one-tap interface, in full Persian and English.

## Get Nova for your platform

| Platform | How to get it |
| --- | --- |
| **Android** | Download the APK from the [latest release](https://github.com/iiviirv/Nova-Client/releases/latest). One `arm64` build, it covers essentially every phone from the last several years. |
| **iPhone / iPad** | Via **TestFlight**: [join link](https://testflight.apple.com/join/bxfK3MyF). (In Iran, install the TestFlight app and accept the invite with a non-Iranian Apple ID, Apple blocks its services in Iran.) |
| **macOS** (Apple Silicon) | Download the macOS zip from the [latest release](https://github.com/iiviirv/Nova-Client/releases/latest), unzip, and open `nova_client.app` (right-click, then Open, the first time). |
| **Windows** (64-bit) | Download `Nova-Windows.zip` from the [latest release](https://github.com/iiviirv/Nova-Client/releases/latest), unzip anywhere, and run `nova_client.exe`. No admin needed. |

The iPhone, macOS and Windows apps share one codebase; Android is a dedicated native build. All of them run the same sing-box core.

## Highlights

- **One tap to connect.** A big Nova logo on the home screen is the connect button. Tap it and you are online; the status and a live timer sit right beside it.
- **Run your own server in two minutes.** Connect your Cloudflare account once, and Nova can deploy a private proxy worker for you, set its password, and save it as your panel, with no terminal and no copy-paste.
- **Find the fastest routes.** Nova Radar scans Cloudflare's network for clean, low-latency IPs and can push them straight to your worker.
- **Bring your own subscription.** Paste a sing-box, Clash, base64, or vless / vmess / trojan link and Nova handles the rest.

## Features in detail

### Connect and browse
- One-tap connect with a clean, single-screen dashboard.
- Live readout of your country (with flag), public IP, ping, and download and upload speed.
- Server list with a country flag and live latency for every config, plus an **Auto / Best server** mode that always routes through the fastest node.
- Mark servers as favorites and filter the list by protocol.
- Works with any subscription format: sing-box, Clash, base64, and vless / vmess / trojan links.

### Build and manage your own server (Cloudflare)
- **Connect to Cloudflare** from inside the app using a secure in-app browser sign-in. You sign in once and your login is saved on the device, so you never have to do it again.
- **See all your workers** in one place and pick one to use as your panel.
- **Deploy a brand new worker** in a couple of taps. Nova creates the storage, uploads the latest proxy code, and reserves your subdomain for you.
- **Set the admin password in the app** (no browser needed). Nova remembers it and signs you in to the panel automatically next time.
- **Manage the panel** from Nova: connection info, security status, network settings, and your custom IP list.

### Nova Radar (clean-IP finder)
- Scans Cloudflare's published IP ranges and measures real connection latency to each one.
- Sorts the results so the fastest, cleanest IPs are on top.
- One button to **send the best IPs straight to your worker**, so your configs use the fastest routes.
- Copy or export the list whenever you want.

### Anti-censorship and routing
- **TLS fragmenting** to get past deep packet inspection.
- **Iran direct-routing** so Iranian sites and apps stay fast and local.
- **WARP / WireGuard** support.
- **Secure DNS** over HTTPS (DoH).
- **Speed mode** and tuned latency testing.
- **Per-app proxy** (split tunneling) and a kill switch.
- Custom diversion rules for advanced routing.

### Insights and tools
- Usage statistics by day, week, month, and year.
- Built-in speed test.
- Backup and restore your whole setup to a local file.

### Designed for everyone
- Full Persian and English, with a proper right-to-left interface.
- Light and dark themes.
- Iran is shown with the Lion and Sun.

## Getting started

1. **Download and install.** Grab the `arm64` APK from the [Releases page](https://github.com/iiviirv/Nova-Client/releases/latest). You may need to allow installing apps from your browser or file manager.
2. **Add a connection.** Either paste a subscription link you already have, or open the Cloudflare section and deploy your own private worker.
3. **Connect.** Tap the Nova logo on the home screen. Android will ask once for VPN permission; allow it.
4. **Tune it (optional).** Open Radar to find faster IPs, or Settings to turn on TLS fragmenting, WARP, secure DNS, and per-app proxy.

## Which file should I download

Android ships a single **`arm64`** APK, which runs on essentially every phone from the last several years, so there is nothing to choose. For desktop, grab the macOS zip (Apple Silicon) or `Nova-Windows.zip` (64-bit Windows) from the latest release.

## Privacy

Nova is a client you control. When you deploy your own Cloudflare worker, the server is yours, on your own account. Your Cloudflare login and panel password are stored only on your device so you do not have to type them again.

## Community

- Website: https://novaproxy.online/
- Telegram: https://t.me/irnova_proxy
- YouTube: https://youtube.com/@novaproxyir
- X: https://x.com/irNovaProxy

## Credits and license

Nova is built on [sing-box](https://github.com/SagerNet/sing-box) and is released under the GPL-3.0 license.

<br>
<div align="center">

# نووا

### اینترنت سریع، رایگان و بدون محدودیت، ساخته‌شده برای ایران.

**[⬇️ دانلود آخرین نسخه](https://github.com/iiviirv/Nova-Client/releases/latest)**

</div>

---

## نووا چیست

نووا یک کلاینت سبک و امروزی وی‌پی‌ان برای **آیفون، اندروید، مک و ویندوز** است. لوگو را لمس کنید تا وصل شوید، و یک داشبورد تمیز کشور، آی‌پی عمومی، پینگ و سرعت زنده دانلود و آپلود را به شما نشان می‌دهد. با اشتراکی که همین حالا دارید کار می‌کند و می‌تواند سرور خصوصی شما را هم بسازد و مدیریت کند، همه از داخل اپ.

## دریافت نووا برای دستگاه شما

| پلتفرم | روش دریافت |
| --- | --- |
| **اندروید** | فایل APK را از [آخرین انتشار](https://github.com/iiviirv/Nova-Client/releases/latest) بگیرید. یک نسخه‌ی `arm64` که تقریباً همه‌ی گوشی‌های چند سال اخیر را پوشش می‌دهد. |
| **آیفون / آیپد** | از طریق **TestFlight**: [لینک عضویت](https://testflight.apple.com/join/bxfK3MyF). در ایران، اپ TestFlight را نصب کرده و دعوت را با Apple ID غیرایرانی بپذیرید. |
| **مک** (Apple Silicon) | فایل زیپ مک را از [آخرین انتشار](https://github.com/iiviirv/Nova-Client/releases/latest) دانلود و باز کنید و `nova_client.app` را اجرا کنید (بار اول راست‌کلیک و سپس Open). |
| **ویندوز** (۶۴ بیتی) | فایل `Nova-Windows.zip` را از [آخرین انتشار](https://github.com/iiviirv/Nova-Client/releases/latest) دانلود کنید، از حالت فشرده خارج کرده و `nova_client.exe` را اجرا کنید. بدون نیاز به دسترسی مدیر. |

نسخه‌های آیفون، مک و ویندوز یک کدِ مشترک دارند؛ اندروید نسخه‌ی native اختصاصی است. همه از هسته‌ی sing-box استفاده می‌کنند.

نووا برای شبکه‌های سخت طراحی شده است. ابزارهای دور زدن سانسوری را که مردم ایران واقعاً به آن نیاز دارند (قطعه‌قطعه‌کردن TLS، WARP، DNS امن، مسیر مستقیم ایران) پشت یک رابط ساده و یک‌لمسی، به‌صورت کامل فارسی و انگلیسی، گرد هم آورده است.

## نکات برجسته

- **اتصال با یک لمس.** لوگوی بزرگ نووا در صفحه اصلی همان دکمه اتصال است. لمس کنید تا آنلاین شوید؛ وضعیت و زمان‌شمار زنده درست کنار آن است.
- **سرور خودتان را در دو دقیقه بسازید.** یک‌بار حساب کلودفلر خود را وصل کنید و نووا می‌تواند یک ورکر پروکسی خصوصی برایتان بسازد، رمزش را تعیین کند و آن را به‌عنوان پنل ذخیره کند، بدون ترمینال و بدون کپی و پیست.
- **سریع‌ترین مسیرها را پیدا کنید.** رادار نووا شبکه کلودفلر را برای آی‌پی‌های تمیز و کم‌پینگ اسکن می‌کند و می‌تواند آن‌ها را مستقیم به ورکر شما بفرستد.
- **اشتراک خودتان را بیاورید.** لینک sing-box، Clash، base64 یا vless / vmess / trojan را بچسبانید و نووا بقیه را انجام می‌دهد.

## امکانات با جزئیات

### اتصال و گشت‌وگذار
- اتصال با یک لمس و داشبورد تمیز و یک‌صفحه‌ای.
- نمایش زنده کشور (با پرچم)، آی‌پی عمومی، پینگ و سرعت دانلود و آپلود.
- فهرست سرورها با پرچم کشور و پینگ زنده برای هر کانفیگ، به‌همراه حالت **خودکار / بهترین سرور** که همیشه از سریع‌ترین گره عبور می‌دهد.
- نشان‌کردن سرورها به‌عنوان علاقه‌مندی و فیلتر فهرست بر اساس پروتکل.
- پشتیبانی از هر نوع اشتراک: sing-box، Clash، base64 و لینک‌های vless / vmess / trojan.

### ساخت و مدیریت سرور خودتان (کلودفلر)
- **اتصال به کلودفلر** از داخل اپ با ورود امن در مرورگر داخلی. یک‌بار وارد می‌شوید و ورودتان روی دستگاه ذخیره می‌شود، پس دیگر هرگز لازم نیست دوباره وارد شوید.
- **دیدن همه ورکرهای شما** در یک‌جا و انتخاب یکی به‌عنوان پنل.
- **ساخت یک ورکر کاملاً جدید** با چند لمس. نووا فضای ذخیره را می‌سازد، آخرین کد پروکسی را آپلود می‌کند و زیردامنه شما را رزرو می‌کند.
- **تعیین رمز مدیریت در اپ** (بدون نیاز به مرورگر). نووا آن را به‌خاطر می‌سپارد و دفعه بعد به‌صورت خودکار وارد پنل می‌شوید.
- **مدیریت پنل** از داخل نووا: اطلاعات اتصال، وضعیت امنیت، تنظیمات شبکه و فهرست آی‌پی سفارشی شما.

### رادار نووا (یابنده آی‌پی تمیز)
- محدوده‌های آی‌پی منتشرشده کلودفلر را اسکن می‌کند و تأخیر اتصال واقعی به هر کدام را اندازه می‌گیرد.
- نتایج را مرتب می‌کند تا سریع‌ترین و تمیزترین آی‌پی‌ها بالا باشند.
- یک دکمه برای **ارسال بهترین آی‌پی‌ها مستقیم به ورکر شما**، تا کانفیگ‌هایتان از سریع‌ترین مسیرها استفاده کنند.
- هر زمان خواستید فهرست را کپی یا خروجی بگیرید.

### دور زدن سانسور و مسیریابی
- **قطعه‌قطعه‌کردن TLS** برای عبور از بازرسی عمیق بسته‌ها.
- **مسیر مستقیم ایران** تا سایت‌ها و اپ‌های ایرانی سریع و محلی بمانند.
- پشتیبانی از **WARP / WireGuard**.
- **DNS امن** روی HTTPS (DoH).
- **حالت سرعت** و تست تأخیر بهینه‌شده.
- **پراکسی هر برنامه** (تونل‌سازی تفکیکی) و کلید قطع اضطراری.
- قوانین مسیریابی سفارشی برای مسیریابی پیشرفته.

### آمار و ابزارها
- آمار مصرف به‌تفکیک روز، هفته، ماه و سال.
- تست سرعت داخلی.
- پشتیبان‌گیری و بازیابی کل تنظیمات در یک فایل محلی.

### طراحی‌شده برای همه
- فارسی و انگلیسی کامل، با رابط درست راست‌به‌چپ.
- تم روشن و تیره.
- ایران با نماد شیر و خورشید نمایش داده می‌شود.

## شروع به کار

1. **دانلود و نصب.** فایل APK نسخه‌ی `arm64` را از [صفحه انتشارها](https://github.com/iiviirv/Nova-Client/releases/latest) بگیرید. ممکن است لازم باشد نصب از مرورگر یا فایل‌منیجر را اجازه دهید.
2. **افزودن اتصال.** یا لینک اشتراکی که دارید را بچسبانید، یا بخش کلودفلر را باز کنید و ورکر خصوصی خود را بسازید.
3. **اتصال.** لوگوی نووا را در صفحه اصلی لمس کنید. اندروید یک‌بار اجازه وی‌پی‌ان می‌خواهد؛ آن را تأیید کنید.
4. **تنظیم دلخواه (اختیاری).** رادار را باز کنید تا آی‌پی‌های سریع‌تر پیدا کنید، یا تنظیمات را باز کنید تا قطعه‌قطعه‌کردن TLS، WARP، DNS امن و پراکسی هر برنامه را روشن کنید.

## کدام فایل را دانلود کنم

اندروید فقط یک نسخه‌ی **`arm64`** دارد که روی تقریباً همه‌ی گوشی‌های چند سال اخیر اجرا می‌شود، پس چیزی برای انتخاب نیست. برای دسکتاپ، زیپ مک (Apple Silicon) یا `Nova-Windows.zip` (ویندوز ۶۴ بیتی) را از آخرین انتشار بگیرید.

## حریم خصوصی

نووا کلاینتی است که در کنترل شماست. وقتی ورکر کلودفلر خودتان را می‌سازید، سرور مال شماست و روی حساب خودتان. ورود کلودفلر و رمز پنل شما فقط روی دستگاه‌تان ذخیره می‌شود تا لازم نباشد دوباره آن را وارد کنید.

## ارتباط با ما

- وب‌سایت: https://novaproxy.online/
- تلگرام: https://t.me/irnova_proxy
- یوتیوب: https://youtube.com/@novaproxyir
- ایکس: https://x.com/irNovaProxy

## اعتبار و مجوز

نووا بر پایه [sing-box](https://github.com/SagerNet/sing-box) ساخته شده و تحت مجوز GPL-3.0 منتشر می‌شود.
