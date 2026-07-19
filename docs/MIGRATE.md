# Migrating from shared hosting to your VPS

Move a live WordPress site from a **cPanel** or **DirectAdmin** shared host onto
your new VPS/VDS — the installer does the heavy lifting (extract, import the
database, fix `wp-config.php`, and rewrite the old URL to your new domain).

> مستندات فارسی در پایین همین صفحه است ⬇️

---

## What you need

1. A **backup of your old site** — any of these works:
   - a **cPanel** full/account backup (`backup-*.tar.gz`),
   - a **DirectAdmin** user backup (`user.*.tar.gz`),
   - or a plain **`.zip` / `.tar.gz` of your site files** *plus* a database
     **`.sql`** (or `.sql.gz`) dump.
2. The backup reachable by the server — either a **direct download URL**, or
   the file **uploaded to the VPS** (e.g. with `scp`).
3. Your new **domain** pointed at (or ready to point at) the VPS.

> You'll still log in with the **same username and password** as your old site —
> the content, users and passwords come across in the database.

---

## Step 1 — Get a backup from your old host

**cPanel:** *Tools → Backup → Download a Full Account Backup* (or *Backup
Wizard*). You get a `backup-*.tar.gz`.

**DirectAdmin:** *Create/Restore Backups → Create Backup* (select everything).
You get a `.tar.gz`.

**Manual (any host):** download your site folder (`public_html`) as a zip via
File Manager/FTP, and export the database from **phpMyAdmin** (*Export → Quick →
SQL*) as a `.sql` file.

---

## Step 2 — Make the backup reachable by the VPS

Pick one:

- **Upload it to the VPS** from your computer:
  ```bash
  scp backup-08.01.2026_your-site.tar.gz root@YOUR_SERVER_IP:/root/
  ```
  Then use the path `/root/backup-08.01.2026_your-site.tar.gz`.

- **Or use a direct download URL** (a link that downloads the file directly).

---

## Step 3 — Run the installer in migration mode

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/ehsanking/One-Click-WordPress-Install/main/install.sh)
```

Answer the questions:

1. **Domain** → your new domain.
2. **Behind a CDN?** → *y* if you use ArvanCloud/Cloudflare/etc., otherwise *n*
   (and optionally get a free SSL certificate).
3. **Migrate from an existing backup?** → **y**
4. **Backup URL or file path** → paste the URL, or the path you uploaded to
   (e.g. `/root/backup-….tar.gz`).

---

## What the script does for you

1. Builds the LEMP stack (Nginx, PHP, MariaDB) with a **fresh random database**.
2. **Extracts** the backup and automatically finds:
   - your WordPress files (`public_html`, wherever they sit in the backup), and
   - the WordPress **database dump** (even a gzipped one, skipping non-WP DBs).
3. Copies the files into `/var/www/<your-domain>`.
4. **Imports** the database into the new random database.
5. Re-points `wp-config.php` at the **new** database name/user/password.
6. Runs **`wp search-replace`** to change every `https://old-domain` →
   `https://new-domain` (safely, even inside serialized data).
7. Fixes file permissions and flushes the cache.

When it finishes, your site is **live on the new domain** and you log in at
`https://your-domain.com/wp-admin` with your **existing** credentials.

---

## After migrating

- **Check the site** and the dashboard. If some links still point to the old
  domain (rare, from hard-coded values), re-run:
  ```bash
  cd /var/www/your-domain.com
  sudo -u www-data wp search-replace 'https://old-domain.com' 'https://new-domain.com' --all-tables --skip-columns=guid
  ```
- **SSL:** if you're behind a CDN, set SSL in the CDN panel; otherwise the
  script's Let's Encrypt certificate already covers you.
- **DNS:** once you've confirmed the site works, point your domain's DNS to the
  VPS IP (or update your CDN's origin).
- **Old host:** keep it until you're 100% happy, then cancel it.

---

## Troubleshooting

| Symptom | Fix |
| --- | --- |
| "No WordPress installation found in the backup" | The archive doesn't contain `wp-load.php`. Make sure it includes your `public_html`/site files, not just the database. |
| "No WordPress database dump found" | Include the `.sql` (or `.sql.gz`) in the backup, or provide a separate files-archive **and** a database export. |
| Site loads but images/links use the old domain | Re-run the `wp search-replace` command shown above. |
| "Error establishing a database connection" | Rare — check `/root/wordpress-credentials.txt` and that `wp-config.php` has the new values. |
| Login doesn't work | Use the **old site's** username/password. If forgotten: `cd /var/www/your-domain.com && sudo -u www-data wp user update <user> --user_pass='NEW-PASS'`. |

---
---

<div dir="rtl">

# مهاجرت از هاست اشتراکی به VPS

یک سایت وردپرسی زنده را از هاست اشتراکی **cPanel** یا **DirectAdmin** به VPS/VDS
جدید منتقل کنید — نصب‌کننده کارهای سنگین را انجام می‌دهد (استخراج، ایمپورت
دیتابیس، اصلاح `wp-config.php` و جایگزینی آدرس قدیمی با دامنه‌ی جدید).

## چه چیزی لازم دارید

۱. یک **بکاپ از سایت قدیمی** — هر کدام از این‌ها کار می‌کند:
   - بکاپ کامل/اکانت **cPanel** (`backup-*.tar.gz`)،
   - بکاپ کاربر **DirectAdmin** (`user.*.tar.gz`)،
   - یا یک **`.zip` / `.tar.gz` از فایل‌های سایت** به‌همراه یک دامپ دیتابیس
     **`.sql`** (یا `.sql.gz`).
۲. بکاپ در دسترس سرور باشد — یا یک **لینک دانلود مستقیم**، یا فایل روی VPS
   **آپلود شده** باشد (مثلاً با `scp`).
۳. **دامنه‌ی** جدیدتان به VPS اشاره کند (یا آماده‌ی اشاره باشد).

> با همان **نام کاربری و رمز عبور** سایت قبلی وارد می‌شوید — محتوا، کاربران و
> رمزها همگی داخل دیتابیس منتقل می‌شوند.

## گام ۱ — گرفتن بکاپ از هاست قدیمی

**cPanel:** مسیر *Tools → Backup → Download a Full Account Backup* (یا *Backup
Wizard*). یک فایل `backup-*.tar.gz` می‌گیرید.

**DirectAdmin:** مسیر *Create/Restore Backups → Create Backup* (همه‌چیز را
انتخاب کنید). یک `.tar.gz` می‌گیرید.

**دستی (هر هاستی):** پوشه‌ی سایت (`public_html`) را از File Manager/FTP به‌صورت
zip دانلود کنید و دیتابیس را از **phpMyAdmin** (*Export → Quick → SQL*) به‌صورت
`.sql` بگیرید.

## گام ۲ — در دسترس قراردادن بکاپ برای VPS

یکی را انتخاب کنید:

- **آپلود روی VPS** از کامپیوترتان:
  ```bash
  scp backup-08.01.2026_your-site.tar.gz root@YOUR_SERVER_IP:/root/
  ```
  سپس مسیر `/root/backup-08.01.2026_your-site.tar.gz` را بدهید.

- **یا یک لینک دانلود مستقیم** (لینکی که مستقیم فایل را دانلود می‌کند).

## گام ۳ — اجرای نصب‌کننده در حالت مهاجرت

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/ehsanking/One-Click-WordPress-Install/main/install.sh)
```

به سؤال‌ها پاسخ دهید:

۱. **دامنه** → دامنه‌ی جدید شما.
۲. **پشت CDN است؟** → اگر از آروان‌کلود/کلودفلر استفاده می‌کنید *y*، وگرنه *n*
   (و در صورت تمایل SSL رایگان بگیرید).
۳. **از بکاپ موجود مهاجرت شود؟** → **y**
۴. **لینک یا مسیر فایل بکاپ** → لینک را بچسبانید، یا مسیری که آپلود کردید (مثلاً
   `/root/backup-….tar.gz`).

## اسکریپت چه کاری برایتان می‌کند

۱. استک LEMP (Nginx، PHP، MariaDB) را با یک **دیتابیس تصادفی جدید** می‌سازد.
۲. بکاپ را **استخراج** می‌کند و خودکار این‌ها را پیدا می‌کند:
   - فایل‌های وردپرس (`public_html`، هر جای بکاپ که باشند)، و
   - **دامپ دیتابیس** وردپرس (حتی gzip‌شده، با رد کردن دیتابیس‌های غیروردپرسی).
۳. فایل‌ها را در `/var/www/<دامنه>` کپی می‌کند.
۴. دیتابیس را در دیتابیس تصادفی جدید **ایمپورت** می‌کند.
۵. `wp-config.php` را به نام/یوزر/رمز **جدید** دیتابیس وصل می‌کند.
۶. با **`wp search-replace`** هر `https://دامنه-قدیمی` را به `https://دامنه-جدید`
   تغییر می‌دهد (به‌صورت امن، حتی داخل داده‌های serialize‌شده).
۷. دسترسی فایل‌ها را اصلاح و کش را فلش می‌کند.

در پایان، سایت شما **روی دامنه‌ی جدید زنده** است و با **همان اطلاعات ورود قبلی**
در `https://your-domain.com/wp-admin` وارد می‌شوید.

## بعد از مهاجرت

- **سایت** و پیشخوان را بررسی کنید. اگر بعضی لینک‌ها هنوز به دامنه‌ی قدیمی اشاره
  می‌کنند (به‌ندرت، از مقادیر هاردکد)، دوباره اجرا کنید:
  ```bash
  cd /var/www/your-domain.com
  sudo -u www-data wp search-replace 'https://old-domain.com' 'https://new-domain.com' --all-tables --skip-columns=guid
  ```
- **SSL:** اگر پشت CDN هستید SSL را از پنل CDN تنظیم کنید؛ وگرنه گواهی Let's
  Encrypt اسکریپت پوشش می‌دهد.
- **DNS:** بعد از اطمینان از درست‌کارکردن سایت، DNS دامنه را به آی‌پی VPS اشاره
  دهید (یا origin سی‌دی‌ان را به‌روز کنید).
- **هاست قدیمی:** تا وقتی ۱۰۰٪ راضی نشده‌اید نگهش دارید، بعد لغوش کنید.

## رفع اشکال

| نشانه | راه‌حل |
| --- | --- |
| «نصب وردپرسی داخل بکاپ پیدا نشد» | آرشیو شامل `wp-load.php` نیست. مطمئن شوید فایل‌های `public_html`/سایت را دارد، نه فقط دیتابیس. |
| «فایل دیتابیس داخل بکاپ پیدا نشد» | فایل `.sql` (یا `.sql.gz`) را در بکاپ بگنجانید، یا یک آرشیو فایل‌ها **و** یک خروجی دیتابیس جدا بدهید. |
| سایت بالا می‌آید ولی تصاویر/لینک‌ها دامنه‌ی قدیمی دارند | دستور `wp search-replace` بالا را دوباره اجرا کنید. |
| «Error establishing a database connection» | به‌ندرت — `/root/wordpress-credentials.txt` و مقادیر جدید در `wp-config.php` را چک کنید. |
| ورود کار نمی‌کند | از یوزر/رمز **سایت قدیمی** استفاده کنید. اگر فراموش شده: `cd /var/www/your-domain.com && sudo -u www-data wp user update <user> --user_pass='رمز-جدید'`. |

</div>
