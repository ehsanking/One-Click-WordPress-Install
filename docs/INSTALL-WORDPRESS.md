# Installing WordPress — Step by Step

This guide explains how to **finish the WordPress installation** in your
browser after `install.sh` has prepared the server, and what to do right
afterwards.

> مستندات فارسی در پایین همین صفحه است ⬇️

---

## 1. Before you start

When `install.sh` finishes, it prints (and saves to
`/root/wordpress-credentials.txt`) four values you will need:

| Field | Example | Where it comes from |
| --- | --- | --- |
| Database name | `wp_a1b2c3d4` | auto-generated |
| Username | `wpu_e5f6g7h8` | auto-generated |
| Password | a 24-character random string | auto-generated |
| Database host | `localhost` | always `localhost` |

Keep this window open or copy the values somewhere safe.

> 💡 If you lost them, read the file again:
> ```bash
> sudo cat /root/wordpress-credentials.txt
> ```

---

## 2. Open your site

In a browser go to:

- `https://your-domain.com` — if SSL was installed by the script, **or**
- `http://your-domain.com` — if the domain is behind a CDN (enable SSL in the
  CDN panel afterwards).

If you see a WordPress screen, the server is working. If you get a
**"connection refused"** or a default Nginx page, see *Troubleshooting* below.

---

## 3. The web installer (the famous 5-minute install)

**Step 1 — Choose your language**
WordPress shows a long list of languages. Pick the one you want (e.g. *English*
or *فارسی*) and click **Continue**.

**Step 2 — "Let's go"**
WordPress explains it needs the database details. Click **Let's go!**

**Step 3 — Database connection**
Fill the form with the credentials the script gave you:

| Field on the page | What to enter |
| --- | --- |
| Database Name | the `wp_…` name |
| Username | the `wpu_…` user |
| Password | the random password |
| Database Host | `localhost` |
| Table Prefix | `wp_` (you may change it for extra hardening, e.g. `wp7x_`) |

Click **Submit**. If the details are correct you'll see *"All right, sparky!"*.

**Step 4 — Run the installation**
Click **Run the installation**.

**Step 5 — Site details** (this is the important security step)

| Field | Advice |
| --- | --- |
| Site Title | Your website name (can be changed later). |
| Username | **Do NOT use `admin`.** Pick something unique, e.g. `siteowner_7q`. |
| Password | Use the strong one WordPress suggests, or your own 16+ char password. |
| Your Email | A real address — used for password resets and notifications. |
| Search engine visibility | Leave **unchecked** if you want Google to index the site; check it only while building. |

Click **Install WordPress**.

**Step 6 — Log in**
Click **Log In**, enter the username/password you just chose, and you're in the
dashboard at `https://your-domain.com/wp-admin`. 🎉

---

## 4. First things to do after install

1. **Settings → Permalinks** → choose **Post name** (better URLs & SEO).
2. **Settings → General** → confirm Site Address uses `https://` if you have SSL.
3. **Appearance → Themes** → delete themes you don't use (keep one default as a
   fallback).
4. **Plugins** → delete the sample plugins (Hello Dolly, Akismet if unused).
5. **Update everything**: Dashboard → Updates → update core, themes, plugins.
6. Read the **[Security guide](SECURITY.md)** and apply the hardening steps.

---

## 5. Useful commands (WP-CLI)

The script also installed **WP-CLI**, so you can manage the site from the
terminal. Run these from the site folder (`/var/www/your-domain.com`):

```bash
cd /var/www/your-domain.com

# Show WordPress version
sudo -u www-data wp core version

# Update core, plugins and themes
sudo -u www-data wp core update
sudo -u www-data wp plugin update --all
sudo -u www-data wp theme update --all

# Install and activate a plugin (example: Wordfence security)
sudo -u www-data wp plugin install wordfence --activate

# Create a new admin user
sudo -u www-data wp user create john john@example.com --role=administrator

# Reset a password
sudo -u www-data wp user update admin --user_pass='NEW-STRONG-PASSWORD'
```

> Running as `www-data` keeps file ownership correct.

---

## 6. Troubleshooting

| Symptom | Cause / Fix |
| --- | --- |
| *Error establishing a database connection* | Wrong DB details. Re-check `sudo cat /root/wordpress-credentials.txt`. Host must be `localhost`. |
| Default Nginx page instead of WordPress | The site config didn't load. Run `sudo nginx -t && sudo systemctl reload nginx`. |
| 502 Bad Gateway | PHP-FPM not running: `sudo systemctl restart php8.1-fpm`. |
| White screen / 500 error | Check logs: `sudo tail -f /var/log/nginx/error.log` and `/var/log/php8.1-fpm.log`. |
| Can't upload large media | Confirm `php.ini` tuning loaded: `php -i | grep upload_max_filesize` (should be 50M). |
| HTTPS not working behind CDN | Set the SSL mode to *Flexible/Full* in the CDN panel. |

---
---

<div dir="rtl">

# نصب وردپرس — مرحله‌به‌مرحله

این راهنما توضیح می‌دهد بعد از اینکه `install.sh` سرور را آماده کرد، چطور **نصب
وردپرس را در مرورگر تکمیل کنید** و بلافاصله بعدش چه کارهایی انجام دهید.

## ۱. قبل از شروع

وقتی `install.sh` تمام می‌شود، چهار مقدار را نمایش می‌دهد (و در فایل
`/root/wordpress-credentials.txt` ذخیره می‌کند) که به آن‌ها نیاز دارید:

| فیلد | نمونه | منبع |
| --- | --- | --- |
| نام دیتابیس | `wp_a1b2c3d4` | خودکار |
| نام کاربری | `wpu_e5f6g7h8` | خودکار |
| رمز عبور | رشته‌ی تصادفی ۲۴ کاراکتری | خودکار |
| هاست دیتابیس | `localhost` | همیشه `localhost` |

این مقادیر را جایی امن نگه دارید.

> 💡 اگر گمشان کردید، دوباره فایل را بخوانید:
> ```bash
> sudo cat /root/wordpress-credentials.txt
> ```

## ۲. باز کردن سایت

در مرورگر بروید به:

- `https://your-domain.com` — اگر اسکریپت SSL نصب کرده، **یا**
- `http://your-domain.com` — اگر دامنه پشت CDN است (بعداً SSL را از پنل CDN
  فعال کنید).

اگر صفحه‌ی وردپرس را دیدید، سرور درست کار می‌کند. اگر خطای **connection
refused** یا صفحه‌ی پیش‌فرض Nginx دیدید، بخش *رفع اشکال* را ببینید.

## ۳. نصب‌کننده‌ی وب (نصب معروف ۵ دقیقه‌ای)

**مرحله ۱ — انتخاب زبان**
وردپرس فهرست بلندی از زبان‌ها نشان می‌دهد. زبان دلخواه (مثلاً *فارسی*) را انتخاب
و روی **Continue/ادامه** کلیک کنید.

**مرحله ۲ — «بزن بریم»**
وردپرس می‌گوید به اطلاعات دیتابیس نیاز دارد. روی **Let's go!/بزن بریم** کلیک کنید.

**مرحله ۳ — اتصال به دیتابیس**
فرم را با اطلاعاتی که اسکریپت داده پر کنید:

| فیلد در صفحه | چه چیزی وارد کنید |
| --- | --- |
| Database Name | نام `wp_…` |
| Username | کاربر `wpu_…` |
| Password | رمز تصادفی |
| Database Host | `localhost` |
| Table Prefix | `wp_` (برای امنیت بیشتر می‌توانید عوض کنید، مثلاً `wp7x_`) |

روی **Submit/ارسال** کلیک کنید. اگر درست باشد پیام موفقیت می‌بینید.

**مرحله ۴ — اجرای نصب**
روی **Run the installation/اجرای نصب** کلیک کنید.

**مرحله ۵ — مشخصات سایت** (این مهم‌ترین مرحله از نظر امنیت است)

| فیلد | توصیه |
| --- | --- |
| عنوان سایت | نام سایت شما (بعداً قابل تغییر). |
| نام کاربری | **هرگز از `admin` استفاده نکنید.** یک نام یکتا بسازید، مثلاً `siteowner_7q`. |
| رمز عبور | از رمز قوی پیشنهادی وردپرس یا رمز ۱۶+ کاراکتری خودتان استفاده کنید. |
| ایمیل شما | یک ایمیل واقعی — برای بازیابی رمز و اعلان‌ها. |
| دیده‌شدن در موتور جستجو | برای ایندکس‌شدن در گوگل **تیک نزنید**؛ فقط هنگام ساخت سایت تیک بزنید. |

روی **Install WordPress/نصب وردپرس** کلیک کنید.

**مرحله ۶ — ورود**
روی **Log In/ورود** کلیک کنید، نام کاربری و رمزی که ساختید را وارد کنید و وارد
پیشخوان `https://your-domain.com/wp-admin` می‌شوید. 🎉

## ۴. اولین کارها بعد از نصب

۱. **تنظیمات → پیوندهای یکتا** → گزینه‌ی **نام نوشته (Post name)** را انتخاب
   کنید (آدرس بهتر و سئوی بهتر).
۲. **تنظیمات → عمومی** → مطمئن شوید آدرس سایت با `https://` است (اگر SSL دارید).
۳. **نمایش → پوسته‌ها** → پوسته‌های بلااستفاده را حذف کنید (یک پوسته‌ی پیش‌فرض
   به‌عنوان پشتیبان نگه دارید).
۴. **افزونه‌ها** → افزونه‌های نمونه را حذف کنید.
۵. **همه‌چیز را بروزرسانی کنید**: پیشخوان → بروزرسانی‌ها.
۶. **[راهنمای امنیت](SECURITY.md)** را بخوانید و مراحل سخت‌سازی را انجام دهید.

## ۵. دستورهای مفید (WP-CLI)

اسکریپت **WP-CLI** را هم نصب کرده، پس می‌توانید سایت را از ترمینال مدیریت کنید.
این دستورها را از پوشه‌ی سایت اجرا کنید (`/var/www/your-domain.com`):

```bash
cd /var/www/your-domain.com

# نمایش نسخه‌ی وردپرس
sudo -u www-data wp core version

# بروزرسانی هسته، افزونه‌ها و پوسته‌ها
sudo -u www-data wp core update
sudo -u www-data wp plugin update --all
sudo -u www-data wp theme update --all

# نصب و فعال‌سازی افزونه (مثال: افزونه‌ی امنیتی Wordfence)
sudo -u www-data wp plugin install wordfence --activate

# ساخت کاربر مدیر جدید
sudo -u www-data wp user create john john@example.com --role=administrator

# تغییر رمز عبور
sudo -u www-data wp user update admin --user_pass='رمز-قوی-جدید'
```

> اجرای دستورها با کاربر `www-data` باعث می‌شود مالکیت فایل‌ها درست بماند.

## ۶. رفع اشکال

| نشانه | علت / راه‌حل |
| --- | --- |
| *Error establishing a database connection* | اطلاعات دیتابیس اشتباه است. دوباره `sudo cat /root/wordpress-credentials.txt` را ببینید. هاست باید `localhost` باشد. |
| صفحه‌ی پیش‌فرض Nginx به‌جای وردپرس | کانفیگ سایت بارگذاری نشده: `sudo nginx -t && sudo systemctl reload nginx`. |
| خطای 502 Bad Gateway | PHP-FPM اجرا نیست: `sudo systemctl restart php8.1-fpm`. |
| صفحه‌ی سفید / خطای 500 | لاگ‌ها را ببینید: `sudo tail -f /var/log/nginx/error.log`. |
| آپلود فایل بزرگ ممکن نیست | بررسی کنید تنظیم php.ini اعمال شده: `php -i | grep upload_max_filesize` (باید 50M باشد). |
| HTTPS پشت CDN کار نمی‌کند | حالت SSL را در پنل CDN روی *Flexible/Full* بگذارید. |

</div>
