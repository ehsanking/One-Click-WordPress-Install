# One-Click WordPress Install

A single command that turns a fresh **Ubuntu** server into a ready-to-use
WordPress host: system update, Nginx, PHP 8.3, MariaDB, ionCube Loader,
tuned `php.ini`, optional Let's Encrypt SSL, and the WordPress files — all
automated, with a random database/user/password generated for you.

> **English** documentation is below. مستندات **فارسی** در پایین همین صفحه آمده است. ⬇️

> ### ⚠️ Supported up to Ubuntu 24.04 LTS
> This installer is supported on **Ubuntu 20.04 / 22.04 / 24.04 LTS**.
> **Ubuntu 25.10 / 26.04 and newer are not supported yet**, because they ship
> **PHP 8.5**, while the **ionCube Loader currently supports PHP only up to
> 8.4**. If you need ionCube (for ionCube-encoded software), install on
> **Ubuntu 24.04 LTS**, where the script sets up PHP 8.3 + ionCube cleanly.

---

## ✨ Features

- 🔄 Updates and upgrades the Ubuntu system
- 📦 Installs all required packages
- 🌐 Installs and configures **Nginx**
- 🔗 Asks for your **domain**
- 🔐 Issues a free **Let's Encrypt SSL** certificate — or **skips SSL** when
  the domain is behind a **CDN** (ArvanCloud / Iranian hosts / Cloudflare),
  where the CDN already handles HTTPS
- 🐘 Installs **PHP** (php-fpm + all common WordPress extensions) — prefers
  **8.3**, auto-detected, falls back to 8.2 / 8.1. (On Ubuntu 26.04+ the only
  available PHP is 8.5, which ionCube can't load yet — see the compatibility
  note above.)
- 🗄️ Installs **MariaDB** (lighter, faster and secure-by-default on Ubuntu)
  and auto-creates a **random** database, user and password
- 🧩 Downloads the matching **ionCube Loader**, installs it into the correct
  path and wires it into `php.ini` (as the first `zend_extension`)
- ⚙️ Tunes `php.ini`: **50M** uploads and **1GB** memory limit
- 📥 Downloads **WordPress** so you finish the famous web installer and pick
  the **language** yourself (the DB credentials are printed for you to enter)
- 🛟 Creates a 2GB swap file automatically if the server has less than 1GB RAM
- 🔥 Basic UFW firewall rules (SSH + Nginx) so you are never locked out

---

## ✅ Requirements

- A fresh **Ubuntu LTS** server — **20.04 / 22.04 / 24.04** (use **24.04 LTS**
  for the newest stack with ionCube). ⚠️ **25.10 / 26.04+ are not supported**
  yet: they ship PHP 8.5 and ionCube only supports up to PHP 8.4.
- `root` access (or `sudo`)
- A **domain** whose DNS already points to the server's IP
  (required only if you want Let's Encrypt SSL)

### Why up to Ubuntu 24.04?

The stack depends on the **ionCube Loader**, which currently provides loaders
for **PHP up to 8.4**. Ubuntu **24.04 LTS** ships PHP 8.3 (and the ondrej PPA
offers 8.4), so ionCube works. Ubuntu **26.04** ships **PHP 8.5**, for which no
ionCube loader exists yet — so the installer will warn and stop rather than
give you a broken, ionCube-less setup. Stick with **24.04 LTS** until ionCube
adds PHP 8.5 support.

---

## 🚀 Installation (one line)

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/ehsanking/One-Click-WordPress-Install/main/install.sh)
```

No `curl`? Use `wget`:

```bash
bash <(wget -qO- https://raw.githubusercontent.com/ehsanking/One-Click-WordPress-Install/main/install.sh)
```

The script asks a few short questions at the start, then runs unattended.

---

## ❓ What it asks you

| Question | Why |
| --- | --- |
| **Domain** | The site address and the Nginx `server_name`. |
| **Behind a CDN?** | If **yes** (ArvanCloud / Iranian hosts / Cloudflare), server-side SSL is skipped because the CDN terminates HTTPS. |
| **Install SSL?** | Shown only when **not** behind a CDN. Issues a free Let's Encrypt certificate. |
| **Email** | Only when SSL is selected — used for renewal notices. |

---

## 🧭 After the script finishes

1. Open your site in a browser:
   - `https://your-domain.com` (if SSL was installed), or
   - `http://your-domain.com` (CDN mode — enable SSL in the CDN panel).
2. On the **first screen, pick your language**.
3. Enter the **database details** the script printed:

   | Field | Value |
   | --- | --- |
   | Database name | `wp_xxxxxxxx` (random) |
   | Username | `wpu_xxxxxxxx` (random) |
   | Password | random 24-char string |
   | Database host | `localhost` |
   | Table prefix | `wp_` |

4. Finish the WordPress install — done! 🎉

The same credentials are also saved, readable by **root only**, at:

```
/root/wordpress-credentials.txt
```

---

## 📚 Guides

- **[Installing WordPress — step by step](docs/INSTALL-WORDPRESS.md)** — how to
  finish the browser-based web installer, plus useful WP-CLI commands and
  troubleshooting.
- **[Security guide](docs/SECURITY.md)** — server and WordPress hardening:
  SSH, firewall, Fail2ban, 2FA, backups, CDN tips and a quick checklist.

---

## 🧩 The stack it installs

| Component | Choice / Notes |
| --- | --- |
| Web server | Nginx |
| PHP | 8.3 by default — auto-detected, falls back to 8.2/8.1 — (php-fpm) with `mysql, curl, gd, mbstring, xml, zip, intl, bcmath, soap, imagick, opcache` |
| Database | **MariaDB** — chosen over MySQL for being lighter/faster on Ubuntu and using secure `unix_socket` auth for root (no root password is ever stored) |
| Encoder | ionCube Loader (auto-matched to the installed PHP version and CPU architecture) |
| SSL | Let's Encrypt via Certbot (optional) |
| Web root | `/var/www/<your-domain>` |

---

## 🔒 Security notes

- The MariaDB **root** account uses `unix_socket` authentication, so no root
  password is created or stored anywhere.
- The WordPress database user is restricted to its **own database only**.
- Random, high-entropy credentials are generated from `/dev/urandom`.
- The credentials file is `chmod 600` (root only).
- A minimal UFW firewall allows only SSH and Nginx.

---

## 🛠️ Troubleshooting

- **Certbot failed?** Your DNS probably doesn't point to the server yet.
  Fix DNS, then re-run:
  ```bash
  certbot --nginx -d your-domain.com -d www.your-domain.com
  ```
- **ionCube not active?** Check it loads:
  ```bash
  php -v   # should mention "with the ionCube PHP Loader"
  ```
- **Lost the DB credentials?** They are in `/root/wordpress-credentials.txt`.
- **Behind ArvanCloud / Cloudflare?** Set the SSL mode in the CDN panel and,
  if you need real visitor IPs, configure `set_real_ip_from` in Nginx with
  your CDN's IP ranges.

---

## ⚠️ Disclaimer

Run this on a **fresh** server. It installs and configures system-level
services and is intended for new VPS/cloud instances.

---
---

<div dir="rtl">

# نصب یک‌کلیکی وردپرس

با **یک خط دستور**، یک سرور تازه‌ی **Ubuntu** را به یک میزبان آماده‌ی وردپرس
تبدیل می‌کند: بروزرسانی سیستم، نصب Nginx، PHP 8.3، MariaDB، ionCube، تنظیم
`php.ini`، گواهی SSL رایگان (اختیاری) و دانلود وردپرس — همه به‌صورت خودکار،
به‌همراه ساخت دیتابیس و یوزر و رمز **تصادفی**.

> ### ⚠️ پشتیبانی تا Ubuntu 24.04 LTS
> این نصب‌کننده روی **Ubuntu 20.04 / 22.04 / 24.04 LTS** پشتیبانی می‌شود.
> **Ubuntu 25.10 / 26.04 و بالاتر هنوز پشتیبانی نمی‌شوند**، چون نسخه‌ی PHP آن‌ها
> **8.5** است، در حالی که **ionCube فعلاً فقط تا PHP 8.4** را پشتیبانی می‌کند.
> اگر به ionCube نیاز دارید (برای نرم‌افزارهای کدشده با ionCube)، روی
> **Ubuntu 24.04 LTS** نصب کنید که اسکریپت PHP 8.3 + ionCube را تمیز برپا می‌کند.

## ✨ امکانات

- 🔄 بروزرسانی و ارتقای کامل سیستم Ubuntu
- 📦 نصب تمام پکیج‌های لازم
- 🌐 نصب و پیکربندی **Nginx**
- 🔗 پرسیدن **دامنه** از شما
- 🔐 گرفتن گواهی **SSL رایگان (Let's Encrypt)** — یا **رد کردن SSL** وقتی دامنه
  پشت **CDN** است (آروان‌کلود / هاست‌های ایران / کلودفلر) که خودِ CDN کار
  HTTPS را انجام می‌دهد
- 🐘 نصب **PHP** (php-fpm به‌همراه همه‌ی افزونه‌های لازم وردپرس) — ترجیحاً
  نسخه‌ی **۸٫۳**، با تشخیص خودکار، و در صورت نیاز بازگشت به ۸٫۲ / ۸٫۱. (روی
  Ubuntu 26.04 تنها نسخه‌ی موجود ۸٫۵ است که ionCube هنوز نمی‌تواند آن را
  بارگذاری کند — به یادداشت سازگاری بالا مراجعه کنید.)
- 🗄️ نصب **MariaDB** (روی Ubuntu سبک‌تر، سریع‌تر و به‌صورت پیش‌فرض امن‌تر) و
  ساخت خودکار دیتابیس و یوزر و رمز **تصادفی**
- 🧩 دانلود **ionCube** مناسب، نصب در مسیر درست و افزودن آن به `php.ini`
  (به‌عنوان اولین `zend_extension`)
- ⚙️ تنظیم `php.ini` روی آپلود **۵۰ مگابایت** و حافظه‌ی **۱ گیگابایت**
- 📥 دانلود **وردپرس** تا خودتان نصب وب را کامل کنید و **زبان** را انتخاب کنید
  (اطلاعات دیتابیس برای واردکردن نمایش داده می‌شود)
- 🛟 ساخت خودکار فایل swap دو گیگابایتی اگر رم سرور کمتر از ۱ گیگ باشد
- 🔥 تنظیمات اولیه‌ی فایروال UFW (SSH و Nginx) تا دسترسی‌تان قطع نشود

## ✅ پیش‌نیازها

- یک سرور **Ubuntu LTS** تازه — **۲۰.۰۴ / ۲۲.۰۴ / ۲۴.۰۴** (برای جدیدترین استک
  همراه ionCube از **۲۴.۰۴ LTS** استفاده کنید). ⚠️ **۲۵.۱۰ / ۲۶.۰۴ و بالاتر هنوز
  پشتیبانی نمی‌شوند**: نسخه‌ی PHP آن‌ها ۸٫۵ است و ionCube فقط تا ۸٫۴ را پشتیبانی می‌کند.
- دسترسی `root` (یا `sudo`)
- یک **دامنه** که DNS آن از قبل به آی‌پی سرور اشاره کند
  (فقط اگر SSL از Let's Encrypt می‌خواهید لازم است)

### چرا تا Ubuntu 24.04؟

این استک به **ionCube Loader** وابسته است که فعلاً لودر را برای **PHP تا 8.4**
ارائه می‌دهد. **Ubuntu 24.04 LTS** نسخه‌ی PHP 8.3 دارد (و مخزن ondrej نسخه‌ی 8.4
را می‌دهد)، پس ionCube کار می‌کند. اما **Ubuntu 26.04** نسخه‌ی **PHP 8.5** دارد که
هنوز هیچ لودر ionCube برایش وجود ندارد — برای همین اسکریپت به‌جای راه‌اندازی یک
نصبِ معیوبِ بدون ionCube، هشدار می‌دهد و متوقف می‌شود. تا وقتی ionCube از PHP 8.5
پشتیبانی کند، روی **24.04 LTS** بمانید.

## 🚀 نصب (یک خط)

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/ehsanking/One-Click-WordPress-Install/main/install.sh)
```

اگر `curl` ندارید، از `wget` استفاده کنید:

```bash
bash <(wget -qO- https://raw.githubusercontent.com/ehsanking/One-Click-WordPress-Install/main/install.sh)
```

اسکریپت در ابتدا چند سؤال کوتاه می‌پرسد و بعد بقیه‌ی کار را خودکار انجام می‌دهد.

## ❓ سؤال‌هایی که می‌پرسد

| سؤال | دلیل |
| --- | --- |
| **دامنه** | آدرس سایت و `server_name` در Nginx. |
| **پشت CDN است؟** | اگر **بله** (آروان‌کلود/هاست ایران/کلودفلر)، SSL روی سرور نصب نمی‌شود چون CDN خودش HTTPS را مدیریت می‌کند. |
| **SSL نصب شود؟** | فقط وقتی **پشت CDN نیستید** نمایش داده می‌شود. گواهی رایگان Let's Encrypt می‌گیرد. |
| **ایمیل** | فقط هنگام انتخاب SSL — برای اعلان‌های تمدید. |

## 🧭 بعد از پایان اسکریپت

۱. سایت را در مرورگر باز کنید:
   - `https://your-domain.com` (اگر SSL نصب شده) یا
   - `http://your-domain.com` (حالت CDN — SSL را از پنل CDN فعال کنید).

۲. در **صفحه‌ی اول، زبان را انتخاب کنید**.

۳. **اطلاعات دیتابیس** را که اسکریپت نمایش داده وارد کنید:

   | فیلد | مقدار |
   | --- | --- |
   | نام دیتابیس | `wp_xxxxxxxx` (تصادفی) |
   | نام کاربری | `wpu_xxxxxxxx` (تصادفی) |
   | رمز عبور | رشته‌ی تصادفی ۲۴ کاراکتری |
   | هاست دیتابیس | `localhost` |
   | پیشوند جدول | `wp_` |

۴. نصب وردپرس را تمام کنید — تمام شد! 🎉

این اطلاعات در فایل زیر هم ذخیره می‌شود (فقط برای **root** قابل خواندن):

```
/root/wordpress-credentials.txt
```

## 📚 راهنماها

- **[نصب وردپرس — مرحله‌به‌مرحله](docs/INSTALL-WORDPRESS.md)** — تکمیل نصب
  وردپرس در مرورگر، به‌همراه دستورهای مفید WP-CLI و رفع اشکال.
- **[راهنمای امنیت](docs/SECURITY.md)** — سخت‌سازی سرور و وردپرس: SSH،
  فایروال، Fail2ban، احراز هویت دومرحله‌ای، پشتیبان‌گیری، نکات CDN و چک‌لیست.

## 🧩 اجزای نصب‌شده

| جزء | توضیح |
| --- | --- |
| وب‌سرور | Nginx |
| PHP | پیش‌فرض ۸٫۳ — با تشخیص خودکار، بازگشت به ۸٫۲/۸٫۱ — (php-fpm) با افزونه‌های `mysql, curl, gd, mbstring, xml, zip, intl, bcmath, soap, imagick, opcache` |
| دیتابیس | **MariaDB** — به‌جای MySQL، چون روی Ubuntu سبک‌تر/سریع‌تر است و برای root از احراز هویت امن `unix_socket` استفاده می‌کند (هیچ رمز root ذخیره نمی‌شود) |
| انکودر | ionCube (به‌صورت خودکار برای نسخه‌ی نصب‌شده‌ی PHP و معماری پردازنده انتخاب می‌شود) |
| SSL | Let's Encrypt با Certbot (اختیاری) |
| مسیر سایت | `/var/www/<دامنه‌ی شما>` |

## 🔒 نکات امنیتی

- کاربر **root** دیتابیس از احراز هویت `unix_socket` استفاده می‌کند، پس هیچ رمز
  root ساخته یا ذخیره نمی‌شود.
- کاربر دیتابیس وردپرس فقط به **دیتابیس خودش** دسترسی دارد.
- رمزهای تصادفی و قوی از `/dev/urandom` ساخته می‌شوند.
- فایل اطلاعات با `chmod 600` فقط برای root قابل خواندن است.
- فایروال UFW فقط SSH و Nginx را باز می‌گذارد.

## 🛠️ رفع اشکال

- **Certbot خطا داد؟** احتمالاً DNS هنوز به سرور اشاره نمی‌کند. بعد از اصلاح
  DNS دوباره اجرا کنید:
  ```bash
  certbot --nginx -d your-domain.com -d www.your-domain.com
  ```
- **ionCube فعال نیست؟** بررسی کنید:
  ```bash
  php -v   # باید عبارت "with the ionCube PHP Loader" را نشان دهد
  ```
- **اطلاعات دیتابیس را گم کردید؟** در `/root/wordpress-credentials.txt` هست.
- **پشت آروان‌کلود/کلودفلر هستید؟** حالت SSL را در پنل CDN تنظیم کنید و اگر
  آی‌پی واقعی بازدیدکنندگان را می‌خواهید، `set_real_ip_from` را با رنج آی‌پی
  CDN در Nginx تنظیم کنید.

## ⚠️ توجه

این اسکریپت را روی سرور **تازه** اجرا کنید. سرویس‌های سطح‌سیستم را نصب و
پیکربندی می‌کند و برای سرورهای جدید VPS/ابری طراحی شده است.

</div>
