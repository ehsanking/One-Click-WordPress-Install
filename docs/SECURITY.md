# Security Guide — Hardening your WordPress server

`install.sh` ships with secure defaults (random DB credentials, `unix_socket`
root auth, restricted DB user, locked-down credentials file, dotfile blocking,
`cgi.fix_pathinfo=0`). This guide teaches you the **extra steps** to keep the
server and the site safe over time.

> مستندات فارسی در پایین همین صفحه است ⬇️

---

## A. Server security

### 1. Keep the system patched
```bash
sudo apt update && sudo apt upgrade -y
# Enable automatic security updates:
sudo apt install -y unattended-upgrades
sudo dpkg-reconfigure --priority=low unattended-upgrades
```

### 2. Harden SSH
Edit `/etc/ssh/sshd_config`:
```
PermitRootLogin no
PasswordAuthentication no      # use SSH keys only
```
Then add your SSH key (`ssh-copy-id user@server`) **before** disabling
passwords, and restart: `sudo systemctl restart ssh`.

> Optional: change the SSH port from 22 to a custom one to cut bot noise.
> If you do, also run `sudo ufw allow <new-port>/tcp` first.

### 3. Turn on the firewall
The script *adds* UFW rules but does not enable the firewall (to avoid locking
you out). Once you've confirmed SSH access, enable it:
```bash
sudo ufw allow OpenSSH
sudo ufw allow 'Nginx Full'
sudo ufw enable
sudo ufw status
```

### 4. Block brute-force with Fail2ban
```bash
sudo apt install -y fail2ban
sudo systemctl enable --now fail2ban
```
This bans IPs that repeatedly fail SSH (and can be extended to WordPress login).

### 5. Correct file permissions
```bash
cd /var/www/your-domain.com
sudo chown -R www-data:www-data .
sudo find . -type d -exec chmod 755 {} \;
sudo find . -type f -exec chmod 644 {} \;
# wp-config.php should be stricter:
sudo chmod 640 wp-config.php
```
Rule of thumb: **never** use `777` on any WordPress file or folder.

---

## B. WordPress security

### 1. Accounts & passwords
- Never use the username `admin`.
- Use long, unique passwords (16+ chars) and a password manager.
- Give each person their own account with the **least role** they need
  (Editor/Author instead of Administrator).

### 2. Enable two-factor authentication (2FA)
Install a 2FA plugin (e.g. *WP 2FA*, *Wordfence Login Security*) and require it
for all admins.

### 3. Limit login attempts
Install *Limit Login Attempts Reloaded* or rely on Wordfence to lock out
repeated failed logins.

### 4. Keep everything updated
Out-of-date plugins/themes are the #1 cause of hacked WordPress sites.
- Enable auto-updates for core and trusted plugins.
- Delete plugins/themes you don't use — inactive code is still a risk.

### 5. Use a security plugin
*Wordfence* or *Sucuri* add a firewall, malware scanning and login protection:
```bash
cd /var/www/your-domain.com
sudo -u www-data wp plugin install wordfence --activate
```

### 6. Disable the in-dashboard file editor
Stops an attacker who steals an admin session from editing PHP directly.
Add to `wp-config.php` (above the *"That's all, stop editing"* line):
```php
define( 'DISALLOW_FILE_EDIT', true );
```

### 7. Refresh security keys (salts)
If you suspect a leak, replace the `AUTH_KEY` … `NONCE_SALT` block in
`wp-config.php` with fresh values from
<https://api.wordpress.org/secret-key/1.1/salt/>. This logs everyone out.

### 8. Protect sensitive files in Nginx
Add inside your `server { … }` block (`/etc/nginx/sites-available/your-domain.com`):
```nginx
# Block direct access to wp-config and other sensitive files
location = /wp-config.php { deny all; }
location ~* /(?:\.git|\.env|composer\.(json|lock))$ { deny all; }

# Stop PHP from executing inside the uploads folder
location ~* /wp-content/uploads/.*\.php$ { deny all; }

# Throttle login & XML-RPC (optional, needs a limit_req_zone in http{})
location = /xmlrpc.php { deny all; }   # block if you don't use the app/API
```
Then test and reload:
```bash
sudo nginx -t && sudo systemctl reload nginx
```

### 9. Always use HTTPS
- If not behind a CDN, the script can issue Let's Encrypt SSL and auto-renews it
  (`certbot renew` runs via a systemd timer; test with `sudo certbot renew --dry-run`).
- In **Settings → General**, make sure both URLs use `https://`.

### 10. Back up regularly
- Plugin route: *UpdraftPlus* to cloud storage (Google Drive, S3…).
- CLI route (database dump):
  ```bash
  mysqldump -u root DBNAME > /root/backup-$(date +%F).sql
  ```
- Keep at least one **off-server** copy. A backup you can restore is your last
  line of defence against ransomware and bad updates.

---

## C. If you are behind a CDN (ArvanCloud / Cloudflare / Iranian hosts)

- Turn on the CDN's **SSL** (Flexible or, better, Full) and its **WAF**.
- **Hide your origin IP**: only allow the CDN's IP ranges to reach port 80/443
  on the server, e.g. with UFW, so attackers can't bypass the CDN.
- Restore **real visitor IPs** in Nginx so logs and security plugins see the
  true client, not the CDN. Add the CDN's ranges:
  ```nginx
  # inside server { } or http { }
  set_real_ip_from 10.0.0.0/8;        # replace with your CDN's IP ranges
  real_ip_header X-Forwarded-For;
  ```
- Enable the CDN's rate-limiting / bot protection for `/wp-login.php` and
  `/xmlrpc.php`.

---

## D. Quick checklist

- [ ] System auto-updates enabled
- [ ] SSH key-only, root login disabled
- [ ] UFW firewall enabled
- [ ] Fail2ban running
- [ ] No user named `admin`, strong passwords everywhere
- [ ] 2FA on all admin accounts
- [ ] Core + plugins + themes updated, unused ones removed
- [ ] Security plugin active (Wordfence/Sucuri)
- [ ] `DISALLOW_FILE_EDIT` set
- [ ] `wp-config.php` and uploads-PHP blocked in Nginx
- [ ] HTTPS everywhere
- [ ] Automated off-server backups

---
---

<div dir="rtl">

# راهنمای امنیت — سخت‌سازی سرور وردپرس

`install.sh` با پیش‌فرض‌های امن می‌آید (رمز دیتابیس تصادفی، احراز هویت
`unix_socket` برای root، کاربر دیتابیس محدود، فایل اطلاعات قفل‌شده، مسدودسازی
dotfileها، و `cgi.fix_pathinfo=0`). این راهنما **مراحل اضافه** را آموزش می‌دهد
تا سرور و سایت در طول زمان امن بمانند.

## الف. امنیت سرور

### ۱. سیستم را همیشه بروز نگه دارید
```bash
sudo apt update && sudo apt upgrade -y
# فعال‌سازی بروزرسانی امنیتی خودکار:
sudo apt install -y unattended-upgrades
sudo dpkg-reconfigure --priority=low unattended-upgrades
```

### ۲. سخت‌سازی SSH
فایل `/etc/ssh/sshd_config` را ویرایش کنید:
```
PermitRootLogin no
PasswordAuthentication no      # فقط با کلید SSH
```
**قبل از** غیرفعال‌کردن رمز، کلید SSH خود را اضافه کنید
(`ssh-copy-id user@server`) و سپس ری‌استارت: `sudo systemctl restart ssh`.

> اختیاری: پورت SSH را از ۲۲ به یک پورت دلخواه تغییر دهید تا حملات ربات‌ها کم
> شود. اگر این کار را کردید، اول `sudo ufw allow <پورت-جدید>/tcp` را بزنید.

### ۳. فعال‌کردن فایروال
اسکریپت قوانین UFW را *اضافه* می‌کند ولی فایروال را فعال نمی‌کند (تا دسترسی شما
قطع نشود). بعد از اطمینان از دسترسی SSH، فعالش کنید:
```bash
sudo ufw allow OpenSSH
sudo ufw allow 'Nginx Full'
sudo ufw enable
sudo ufw status
```

### ۴. جلوگیری از حمله‌ی Brute-force با Fail2ban
```bash
sudo apt install -y fail2ban
sudo systemctl enable --now fail2ban
```
این کار آی‌پی‌هایی که مکرراً در ورود SSH شکست می‌خورند را مسدود می‌کند.

### ۵. سطح دسترسی درست فایل‌ها
```bash
cd /var/www/your-domain.com
sudo chown -R www-data:www-data .
sudo find . -type d -exec chmod 755 {} \;
sudo find . -type f -exec chmod 644 {} \;
# wp-config.php باید سخت‌گیرانه‌تر باشد:
sudo chmod 640 wp-config.php
```
قانون کلی: **هرگز** روی هیچ فایل یا پوشه‌ی وردپرس از `777` استفاده نکنید.

## ب. امنیت وردپرس

### ۱. حساب‌ها و رمزها
- هرگز از نام کاربری `admin` استفاده نکنید.
- رمزهای بلند و یکتا (۱۶+ کاراکتر) و یک مدیر رمز به‌کار ببرید.
- به هر فرد یک حساب جدا با **کمترین نقش لازم** بدهید (نویسنده/ویرایشگر به‌جای
  مدیر کل).

### ۲. فعال‌کردن احراز هویت دومرحله‌ای (2FA)
یک افزونه‌ی 2FA (مثل *WP 2FA* یا *Wordfence Login Security*) نصب و برای همه‌ی
مدیران اجباری کنید.

### ۳. محدودکردن تلاش‌های ورود
افزونه‌ی *Limit Login Attempts Reloaded* را نصب کنید یا از Wordfence استفاده
کنید تا ورودهای ناموفق مکرر مسدود شوند.

### ۴. همه‌چیز را بروز نگه دارید
افزونه/پوسته‌ی قدیمی شماره‌یک علت هک‌شدن سایت‌های وردپرسی است.
- بروزرسانی خودکار را برای هسته و افزونه‌های مطمئن فعال کنید.
- افزونه/پوسته‌ی بلااستفاده را حذف کنید — کد غیرفعال هم خطر است.

### ۵. استفاده از افزونه‌ی امنیتی
*Wordfence* یا *Sucuri* فایروال، اسکن بدافزار و محافظت ورود اضافه می‌کنند:
```bash
cd /var/www/your-domain.com
sudo -u www-data wp plugin install wordfence --activate
```

### ۶. غیرفعال‌کردن ویرایشگر فایل در پیشخوان
جلوی مهاجمی که نشست مدیر را دزدیده می‌گیرد تا نتواند مستقیم PHP ویرایش کند.
به `wp-config.php` اضافه کنید (بالای خط *"That's all, stop editing"*):
```php
define( 'DISALLOW_FILE_EDIT', true );
```

### ۷. تازه‌سازی کلیدهای امنیتی (salts)
اگر به نشت اطلاعات مشکوک شدید، بلوک `AUTH_KEY` تا `NONCE_SALT` در
`wp-config.php` را با مقادیر تازه از این آدرس جایگزین کنید:
<https://api.wordpress.org/secret-key/1.1/salt/> — این کار همه را از حساب خارج
می‌کند.

### ۸. محافظت از فایل‌های حساس در Nginx
داخل بلوک `server { … }` اضافه کنید
(`/etc/nginx/sites-available/your-domain.com`):
```nginx
# مسدودکردن دسترسی مستقیم به wp-config و فایل‌های حساس
location = /wp-config.php { deny all; }
location ~* /(?:\.git|\.env|composer\.(json|lock))$ { deny all; }

# جلوگیری از اجرای PHP در پوشه‌ی uploads
location ~* /wp-content/uploads/.*\.php$ { deny all; }

# مسدودکردن XML-RPC اگر استفاده نمی‌کنید
location = /xmlrpc.php { deny all; }
```
سپس تست و ری‌لود کنید:
```bash
sudo nginx -t && sudo systemctl reload nginx
```

### ۹. همیشه از HTTPS استفاده کنید
- اگر پشت CDN نیستید، اسکریپت می‌تواند SSL رایگان Let's Encrypt بگیرد که خودکار
  تمدید می‌شود (با `sudo certbot renew --dry-run` تست کنید).
- در **تنظیمات → عمومی** مطمئن شوید هر دو آدرس با `https://` هستند.

### ۱۰. پشتیبان‌گیری منظم
- روش افزونه: *UpdraftPlus* به فضای ابری (گوگل‌درایو، S3…).
- روش خط فرمان (دامپ دیتابیس):
  ```bash
  mysqldump -u root DBNAME > /root/backup-$(date +%F).sql
  ```
- حداقل یک نسخه را **خارج از سرور** نگه دارید. پشتیبانی که بتوانید بازگردانید،
  آخرین خط دفاع شما در برابر باج‌افزار و بروزرسانی‌های خراب است.

## ج. اگر پشت CDN هستید (آروان‌کلود / کلودفلر / هاست‌های ایران)

- **SSL** سی‌دی‌ان (Flexible یا بهتر Full) و **WAF** آن را روشن کنید.
- **آی‌پی اصلی سرور (origin) را مخفی کنید**: فقط رنج آی‌پی‌های CDN اجازه‌ی دسترسی
  به پورت ۸۰/۴۴۳ سرور را داشته باشند (مثلاً با UFW) تا مهاجم نتواند CDN را دور
  بزند.
- **آی‌پی واقعی بازدیدکنندگان** را در Nginx بازیابی کنید تا لاگ‌ها و افزونه‌های
  امنیتی آی‌پی واقعی را ببینند:
  ```nginx
  # داخل server { } یا http { }
  set_real_ip_from 10.0.0.0/8;        # با رنج آی‌پی CDN خود جایگزین کنید
  real_ip_header X-Forwarded-For;
  ```
- محدودسازی نرخ / محافظت ربات CDN را برای `/wp-login.php` و `/xmlrpc.php` فعال
  کنید.

## د. چک‌لیست سریع

- [ ] بروزرسانی خودکار سیستم فعال است
- [ ] SSH فقط با کلید، ورود root غیرفعال
- [ ] فایروال UFW فعال است
- [ ] Fail2ban در حال اجراست
- [ ] هیچ کاربری به نام `admin` نیست، همه‌جا رمز قوی
- [ ] 2FA روی همه‌ی حساب‌های مدیر
- [ ] هسته + افزونه‌ها + پوسته‌ها بروز، بلااستفاده‌ها حذف
- [ ] افزونه‌ی امنیتی فعال (Wordfence/Sucuri)
- [ ] `DISALLOW_FILE_EDIT` تنظیم شده
- [ ] `wp-config.php` و اجرای PHP در uploads در Nginx مسدود است
- [ ] HTTPS همه‌جا
- [ ] پشتیبان‌گیری خودکار خارج از سرور

</div>
