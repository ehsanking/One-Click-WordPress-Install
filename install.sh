#!/usr/bin/env bash
#
# One-Click WordPress Install
# ---------------------------
# Automated WordPress stack installer for Ubuntu servers.
#
#   - Update & upgrade the system
#   - Install required packages
#   - Install Nginx
#   - Ask for the domain and (optionally) issue a free Let's Encrypt SSL
#     certificate, OR skip SSL when the domain sits behind a CDN
#     (e.g. ArvanCloud / Iranian hosts / Cloudflare).
#   - Install PHP (php-fpm + extensions); prefers 8.3, falls back to 8.2/8.1
#     and adapts the rest of the install to whatever version is present
#   - Install MariaDB and auto-create a random database, user and password
#   - Download & install the correct ionCube Loader and wire it into php.ini
#   - Tune php.ini  (upload 100M, memory_limit 1024M)
#   - Speed pack: Redis object cache, OPcache tuning, Nginx gzip
#   - Automatic daily backups (wp-backup / wp-restore, kept in /root/backups)
#   - A friendly management menu: `wpctl` (status, backup, update, SSL, …)
#   - Enable security hardening (UFW firewall, Fail2ban, auto security updates)
#   - Either: download WordPress so the user finishes the famous web installer
#     (picking the language) using the database credentials we print,
#     OR: MIGRATE an existing site from a cPanel / DirectAdmin backup (or a
#     files-archive + .sql dump) — extract, import the DB into the fresh
#     database, re-point wp-config.php, and search-replace the old URL.
#
# Usage (one line):
#   bash <(curl -fsSL https://raw.githubusercontent.com/ehsanking/One-Click-WordPress-Install/main/install.sh)
#
# Supported on Ubuntu 20.04 / 22.04 / 24.04 LTS.
# NOTE: Ubuntu 25.10 / 26.04+ ship PHP 8.5, which the ionCube Loader does not
# support yet (ionCube currently supports PHP up to 8.4). For ionCube-encoded
# software, use Ubuntu 24.04 LTS.

set -euo pipefail

# ---------------------------------------------------------------------------
# Constants & globals
# ---------------------------------------------------------------------------
# PHP versions to try, in order of preference. Capped at 8.3 on purpose:
# newer than 8.3 isn't always covered by an ionCube loader yet, and 8.0/older
# are end-of-life. The first version that installs cleanly wins, and the rest
# of the script adapts to whatever actually got installed.
readonly PHP_CANDIDATES=(8.3 8.2 8.1)
# When the running Ubuntu is too new for the ondrej PPA (no Release file yet),
# the PPA is pinned to this well-supported LTS codename so PHP is installable.
readonly PHP_PPA_FALLBACK_CODENAME="noble"
PHP_VERSION=""   # resolved at runtime by install_php()

readonly CRED_FILE="/root/wordpress-credentials.txt"
readonly IONCUBE_BASE_URL="https://downloads.ioncube.com/loader_downloads"

DOMAIN=""
BEHIND_CDN="no"
INSTALL_SSL="no"
SSL_EMAIL=""
DB_NAME=""
DB_USER=""
DB_PASS=""
WEBROOT=""
INSTALL_MODE="fresh"   # "fresh" = new install, "migrate" = restore a backup
BACKUP_SRC=""          # URL or local path to a cPanel/DirectAdmin/zip backup
WP_PREFIX="wp_"        # table prefix (detected from the backup in migrate mode)

# ---------------------------------------------------------------------------
# Pretty logging
# ---------------------------------------------------------------------------
if [[ -t 1 ]]; then
  C_RESET=$'\033[0m'; C_RED=$'\033[1;31m'; C_GREEN=$'\033[1;32m'
  C_YELLOW=$'\033[1;33m'; C_BLUE=$'\033[1;34m'; C_CYAN=$'\033[1;36m'
else
  C_RESET=""; C_RED=""; C_GREEN=""; C_YELLOW=""; C_BLUE=""; C_CYAN=""
fi

log()   { printf '%s\n' "${C_BLUE}==>${C_RESET} $*"; }
ok()    { printf '%s\n' "${C_GREEN}[OK]${C_RESET} $*"; }
warn()  { printf '%s\n' "${C_YELLOW}[!]${C_RESET} $*" >&2; }
err()   { printf '%s\n' "${C_RED}[ERROR]${C_RESET} $*" >&2; }
step()  { printf '\n%s\n' "${C_CYAN}### $* ###${C_RESET}"; }

on_error() {
  local exit_code=$?
  err "Installation failed (line $1, exit code ${exit_code})."
  err "نصب با خطا متوقف شد. خطوط بالا را بررسی کنید."
  exit "${exit_code}"
}
trap 'on_error $LINENO' ERR

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

# Read a line from the real terminal so the script works when piped
# through `curl ... | bash` as well as `bash <(curl ...)`.
ask() {
  local prompt="$1" default="${2:-}" reply
  if [[ -n "${default}" ]]; then
    printf '%s [%s]: ' "${prompt}" "${default}" >/dev/tty
  else
    printf '%s: ' "${prompt}" >/dev/tty
  fi
  read -r reply </dev/tty || true
  printf '%s' "${reply:-${default}}"
}

# Yes/No question -> returns 0 for yes, 1 for no.
ask_yn() {
  local prompt="$1" default="${2:-y}" reply
  while true; do
    reply="$(ask "${prompt} (y/n)" "${default}")"
    case "${reply,,}" in
      y|yes) return 0 ;;
      n|no)  return 1 ;;
      *)     warn "Please answer y or n / لطفاً y یا n وارد کنید." ;;
    esac
  done
}

# Generate a random string:  gen <charset> <length>
# Using process substitution avoids SIGPIPE tripping `set -o pipefail`.
gen() { head -c "$2" <(LC_ALL=C tr -dc "$1" </dev/urandom); }

# Path to the active (non-disabled) ondrej PPA source file, if any.
ondrej_source_file() {
  grep -rls 'ondrej' /etc/apt/sources.list.d/ 2>/dev/null \
    | grep -v '\.disabled$' | head -n1 || true
}

require_root() {
  if [[ "${EUID}" -ne 0 ]]; then
    err "This script must be run as root (use sudo)."
    err "این اسکریپت باید با کاربر root اجرا شود (از sudo استفاده کنید)."
    exit 1
  fi
}

require_ubuntu() {
  if [[ ! -r /etc/os-release ]]; then
    err "Cannot detect the operating system."; exit 1
  fi
  # shellcheck disable=SC1091
  . /etc/os-release
  if [[ "${ID:-}" != "ubuntu" ]]; then
    warn "This script is designed for Ubuntu. Detected: ${PRETTY_NAME:-unknown}"
    ask_yn "Continue anyway? / به‌هرحال ادامه می‌دهید؟" "n" || exit 1
  else
    ok "Detected ${PRETTY_NAME}"
  fi
}

validate_domain() {
  [[ "$1" =~ ^([a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?\.)+[a-zA-Z]{2,}$ ]]
}

# ---------------------------------------------------------------------------
# Interactive questions (asked up-front so the rest can run unattended)
# ---------------------------------------------------------------------------
collect_input() {
  step "Configuration / پیکربندی"

  while true; do
    DOMAIN="$(ask 'Enter your domain (e.g. example.com) / دامنه را وارد کنید')"
    DOMAIN="${DOMAIN#http://}"; DOMAIN="${DOMAIN#https://}"; DOMAIN="${DOMAIN%%/*}"
    DOMAIN="${DOMAIN#www.}"
    if validate_domain "${DOMAIN}"; then
      break
    fi
    warn "Invalid domain. / دامنه نامعتبر است."
  done
  ok "Domain: ${DOMAIN}"

  echo
  log "If your domain is behind a CDN (ArvanCloud, Iranian hosts, Cloudflare),"
  log "the CDN already terminates SSL, so we should NOT issue a certificate here."
  log "اگر دامنه پشت CDN است (آروان‌کلود/هاست ایران/کلودفلر)، SSL را روی سرور نصب نمی‌کنیم."

  if ask_yn "Is the domain behind a CDN? / آیا دامنه پشت CDN است؟" "n"; then
    BEHIND_CDN="yes"
    INSTALL_SSL="no"
    ok "CDN mode: SSL on the server will be skipped."
  else
    BEHIND_CDN="no"
    if ask_yn "Install a free Let's Encrypt SSL certificate? / گواهی SSL رایگان نصب شود؟" "y"; then
      INSTALL_SSL="yes"
      while true; do
        SSL_EMAIL="$(ask 'Email for SSL renewal notices / ایمیل برای اعلان تمدید SSL')"
        [[ "${SSL_EMAIL}" =~ ^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$ ]] && break
        warn "Invalid email. / ایمیل نامعتبر است."
      done
    fi
  fi

  # --- Fresh install or migrate an existing site? -----------------------
  echo
  log "Start FRESH, or MIGRATE an existing site from a cPanel / DirectAdmin"
  log "backup (or a .zip/.tar.gz of the files plus a .sql dump)?"
  log "نصب تازه یا مهاجرت از بکاپ cPanel/DirectAdmin (یا zip فایل‌ها + فایل sql)؟"
  if ask_yn "Migrate from an existing backup? / از بکاپ موجود مهاجرت شود؟" "n"; then
    INSTALL_MODE="migrate"
    log "Give a direct download URL, or upload the backup to the server first"
    log "(e.g. with scp) and give its path."
    log "یک لینک دانلود مستقیم بدهید، یا بکاپ را اول روی سرور بگذارید و مسیرش را بدهید."
    while true; do
      BACKUP_SRC="$(ask 'Backup URL or file path / لینک یا مسیر فایل بکاپ')"
      if [[ "${BACKUP_SRC}" =~ ^https?:// ]] || [[ -f "${BACKUP_SRC}" ]]; then
        break
      fi
      warn "Enter a valid http(s) URL or an existing file path."
      warn "یک لینک http(s) یا مسیر فایل موجود وارد کنید."
    done
    ok "Migration mode from: ${BACKUP_SRC}"
  fi
}

# ---------------------------------------------------------------------------
# Installation steps
# ---------------------------------------------------------------------------
update_system() {
  step "1/9  Updating & upgrading the system / بروزرسانی سیستم"
  export DEBIAN_FRONTEND=noninteractive
  export NEEDRESTART_MODE=a

  if ! apt-get update -y; then
    warn "An apt repository failed to refresh (often a stale third-party PPA)."
    # A broken ondrej PPA left over from a previous run breaks every apt call.
    # Disable it here; the PHP step re-adds and pins it correctly.
    local stale
    stale="$(ondrej_source_file)"
    if [[ -n "${stale}" ]]; then
      warn "Disabling stale ondrej PPA: ${stale}"
      mv "${stale}" "${stale}.disabled" 2>/dev/null || true
    fi
    apt-get update -y || warn "Continuing with cached package lists."
  fi

  apt-get upgrade -y || warn "Upgrade reported issues; continuing."
  ok "System updated."
}

install_base_packages() {
  step "2/9  Installing base packages / نصب پکیج‌های پایه"
  apt-get install -y \
    software-properties-common ca-certificates lsb-release apt-transport-https \
    curl wget unzip tar gnupg2 git ufw
  ok "Base packages installed."
}

ensure_swap() {
  # WordPress + PHP can be memory hungry; make sure at least ~1GB is available.
  local mem_mb swap_mb
  mem_mb=$(awk '/MemTotal/ {printf "%d", $2/1024}' /proc/meminfo)
  swap_mb=$(awk '/SwapTotal/ {printf "%d", $2/1024}' /proc/meminfo)
  if (( mem_mb + swap_mb < 1024 )) && [[ ! -f /swapfile ]]; then
    log "RAM is below 1GB; creating a 2GB swap file / ساخت فایل swap چون رم کمتر از ۱ گیگ است"
    fallocate -l 2G /swapfile || dd if=/dev/zero of=/swapfile bs=1M count=2048
    chmod 600 /swapfile
    mkswap /swapfile
    swapon /swapfile
    grep -q '/swapfile' /etc/fstab || echo '/swapfile none swap sw 0 0' >>/etc/fstab
    ok "2GB swap enabled."
  fi
}

install_nginx() {
  step "3/9  Installing Nginx / نصب Nginx"
  apt-get install -y nginx
  systemctl enable --now nginx
  # The firewall is configured and enabled later, in harden_system().
  ok "Nginx installed and running."
}

# Add the ondrej/php PPA and make sure its package index is usable. On very
# new Ubuntu releases the PPA has no Release file yet, so we pin it to a
# supported LTS codename instead of letting `apt-get update` fail the run.
setup_php_repo() {
  local codename ppa_file
  codename="$(. /etc/os-release && echo "${VERSION_CODENAME:-}")"

  log "Adding the ondrej/php PPA (multiple PHP versions) ..."
  add-apt-repository -y ppa:ondrej/php >/dev/null 2>&1 || true

  if apt-get update -y >/dev/null 2>&1; then
    ok "Package lists updated."
    return 0
  fi

  # The update failed — most likely the PPA has nothing for this codename.
  ppa_file="$(ondrej_source_file)"
  if [[ -n "${ppa_file}" && -n "${codename}" && "${codename}" != "${PHP_PPA_FALLBACK_CODENAME}" ]]; then
    warn "ondrej PPA has no packages for '${codename}'; pinning to '${PHP_PPA_FALLBACK_CODENAME}'."
    sed -i "s/\b${codename}\b/${PHP_PPA_FALLBACK_CODENAME}/g" "${ppa_file}"
  fi
  apt-get update -y >/dev/null 2>&1 || true
}

install_php() {
  step "4/9  Installing PHP (max 8.3) / نصب PHP (حداکثر ۸٫۳)"
  setup_php_repo

  # Try each candidate version until the core packages install cleanly.
  local v core_ok=""
  for v in "${PHP_CANDIDATES[@]}"; do
    log "Trying PHP ${v} ..."
    if apt-get install -y \
        "php${v}-fpm" "php${v}-cli" "php${v}-common" "php${v}-mysql"; then
      PHP_VERSION="${v}"
      core_ok="yes"
      break
    fi
    warn "PHP ${v} is not installable here; trying the next version."
  done

  # Last resort: no preferred (<=8.3) version is packaged for this OS — e.g. a
  # brand-new Ubuntu the ondrej PPA hasn't caught up with. Offer the PHP the
  # distribution ships natively. ionCube supports up to PHP 8.4, so this still
  # produces a working, encoder-compatible stack. We ask first so we never
  # silently exceed the 8.3 preference.
  if [[ -z "${core_ok}" ]]; then
    warn "PHP 8.1/8.2/8.3 are not available from the ondrej PPA on this OS."

    # Drop the (possibly pinned) ondrej PPA so we cleanly use the OS packages.
    local ondrej_src
    ondrej_src="$(ondrej_source_file)"
    if [[ -n "${ondrej_src}" ]]; then
      mv "${ondrej_src}" "${ondrej_src}.disabled" 2>/dev/null || true
      apt-get update -y >/dev/null 2>&1 || true
    fi

    local native_pkg native_ver
    native_pkg="$(apt-cache depends php-fpm 2>/dev/null \
      | grep -oE 'php[0-9]+\.[0-9]+-fpm' | head -n1 || true)"
    native_ver="${native_pkg#php}"; native_ver="${native_ver%-fpm}"

    if [[ -n "${native_ver}" ]]; then
      # ionCube currently ships loaders only up to PHP 8.4. If the OS-native PHP
      # is newer (e.g. 8.5 on Ubuntu 26.04) warn loudly and default to "no",
      # because ionCube-encoded software would not run.
      local default_ans="y"
      if [[ "$(printf '%s\n8.4\n' "${native_ver}" | sort -V | tail -n1)" != "8.4" ]]; then
        warn "ionCube has no loader for PHP ${native_ver} yet — ionCube would be skipped."
        warn "ionCube برای PHP ${native_ver} هنوز لودر ندارد — ionCube نصب نخواهد شد."
        warn "For ionCube-encoded software, use Ubuntu 24.04 LTS instead."
        default_ans="n"
      fi
      log "This system ships PHP ${native_ver} natively."
      log "این سیستم به‌صورت پیش‌فرض PHP ${native_ver} دارد."
      if ask_yn "Install native PHP ${native_ver} anyway? / با این حال نصب شود؟" "${default_ans}"; then
        if apt-get install -y \
            "php${native_ver}-fpm" "php${native_ver}-cli" \
            "php${native_ver}-common" "php${native_ver}-mysql"; then
          PHP_VERSION="${native_ver}"
          core_ok="yes"
        fi
      fi
    fi
  fi

  if [[ -z "${core_ok}" ]]; then
    err "No ionCube-compatible PHP (<= 8.4) could be installed on this system."
    err "Ubuntu 25.10 / 26.04+ ship PHP 8.5, which ionCube does not support yet."
    err "Please use Ubuntu 24.04 LTS (or 22.04), then re-run."
    err "اوبونتو ۲۶.۰۴ نسخه‌ی PHP 8.5 دارد که ionCube هنوز پشتیبانی نمی‌کند."
    err "لطفاً روی Ubuntu 24.04 LTS (یا 22.04) اجرا کنید."
    exit 1
  fi

  # Detect the version actually provided by the php<ver> binary, just in case.
  PHP_VERSION="$("php${PHP_VERSION}" -r 'echo PHP_MAJOR_VERSION.".".PHP_MINOR_VERSION;')"
  ok "PHP ${PHP_VERSION} core installed."

  # Extensions are best-effort: a single unavailable package on a pinned repo
  # must not abort the whole installation.
  local ext
  for ext in curl gd mbstring xml zip intl bcmath soap imagick opcache; do
    apt-get install -y "php${PHP_VERSION}-${ext}" \
      || warn "Optional extension php${PHP_VERSION}-${ext} was not installed."
  done

  systemctl enable --now "php${PHP_VERSION}-fpm"
  ok "PHP ${PHP_VERSION} installed."
}

install_database() {
  step "5/9  Installing MariaDB / نصب دیتابیس MariaDB"
  apt-get install -y mariadb-server mariadb-client
  systemctl enable --now mariadb

  # Generate random credentials.
  DB_NAME="wp_$(gen 'a-z0-9' 8)"
  DB_USER="wpu_$(gen 'a-z0-9' 8)"
  DB_PASS="$(gen 'A-Za-z0-9' 24)"

  # MariaDB on Ubuntu authenticates root via unix_socket, so `mysql` works
  # without a password. We never store a root password anywhere.
  mysql <<-SQL
		DELETE FROM mysql.user WHERE User='';
		DROP DATABASE IF EXISTS test;
		DELETE FROM mysql.db WHERE Db='test' OR Db='test\\_%';
		CREATE DATABASE \`${DB_NAME}\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
		CREATE USER '${DB_USER}'@'localhost' IDENTIFIED BY '${DB_PASS}';
		GRANT ALL PRIVILEGES ON \`${DB_NAME}\`.* TO '${DB_USER}'@'localhost';
		FLUSH PRIVILEGES;
	SQL
  ok "Database, user and password created."
}

install_ioncube() {
  step "6/9  Installing ionCube Loader / نصب ionCube"
  local arch tarball tmpdir ext_dir so_file

  case "$(uname -m)" in
    x86_64|amd64)   arch="x86-64" ;;
    aarch64|arm64)  arch="aarch64" ;;
    *) warn "Unsupported CPU architecture for ionCube: $(uname -m). Skipping."; return 0 ;;
  esac

  tarball="ioncube_loaders_lin_${arch}.tar.gz"
  tmpdir="$(mktemp -d)"
  log "Downloading ${tarball} ..."
  wget -q "${IONCUBE_BASE_URL}/${tarball}" -O "${tmpdir}/${tarball}"
  tar -xzf "${tmpdir}/${tarball}" -C "${tmpdir}"

  so_file="${tmpdir}/ioncube/ioncube_loader_lin_${PHP_VERSION}.so"
  if [[ ! -f "${so_file}" ]]; then
    warn "ionCube loader for PHP ${PHP_VERSION} not found in the archive. Skipping."
    rm -rf "${tmpdir}"
    return 0
  fi

  # Detect the active PHP extension directory.
  ext_dir="$("php${PHP_VERSION}" -r 'echo ini_get("extension_dir");')"
  install -m 644 "${so_file}" "${ext_dir}/ioncube_loader_lin_${PHP_VERSION}.so"

  # The ionCube loader must be the FIRST zend_extension, so we write it to a
  # conf.d file prefixed with 00- (loaded before everything else) for both
  # the FPM and CLI SAPIs.
  local ini_line="zend_extension=${ext_dir}/ioncube_loader_lin_${PHP_VERSION}.so"
  local sapi
  for sapi in fpm cli; do
    printf '%s\n' "${ini_line}" > "/etc/php/${PHP_VERSION}/${sapi}/conf.d/00-ioncube.ini"
  done

  rm -rf "${tmpdir}"
  systemctl restart "php${PHP_VERSION}-fpm"

  if "php${PHP_VERSION}" -v 2>/dev/null | grep -qi ioncube; then
    ok "ionCube Loader is active."
  else
    warn "ionCube was installed but is not reported by 'php -v'. Please verify manually."
  fi
}

tune_php() {
  step "7/9  Tuning php.ini (100M uploads, 1GB memory) / تنظیم php.ini"
  local sapi ini_dir
  for sapi in fpm cli; do
    ini_dir="/etc/php/${PHP_VERSION}/${sapi}/conf.d"
    cat > "${ini_dir}/99-wordpress.ini" <<-INI
		; One-Click WordPress Install tuning
		upload_max_filesize = 100M
		post_max_size = 128M
		memory_limit = 1024M
		max_execution_time = 300
		max_input_time = 300
		max_input_vars = 5000
		file_uploads = On
		cgi.fix_pathinfo = 0
	INI
  done
  systemctl restart "php${PHP_VERSION}-fpm"
  ok "php.ini tuned (upload 100M, memory_limit 1024M)."
}

# Install WP-CLI once (used for fresh downloads, migration and maintenance).
ensure_wp_cli() {
  if ! command -v wp >/dev/null; then
    curl -fsSL https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar \
      -o /usr/local/bin/wp
    chmod +x /usr/local/bin/wp
  fi
}

# Apply the standard WordPress ownership/permissions to the web root.
fix_webroot_perms() {
  chown -R www-data:www-data "${WEBROOT}"
  find "${WEBROOT}" -type d -exec chmod 755 {} \;
  find "${WEBROOT}" -type f -exec chmod 644 {} \;
  [[ -f "${WEBROOT}/wp-config.php" ]] && chmod 640 "${WEBROOT}/wp-config.php"
}

download_wordpress() {
  step "8/9  Downloading WordPress / دانلود وردپرس"
  WEBROOT="/var/www/${DOMAIN}"
  ensure_wp_cli

  mkdir -p "${WEBROOT}"
  # Download the latest WordPress core. The language is chosen by the user
  # later, on the first screen of the web installer.
  wp core download --path="${WEBROOT}" --allow-root --force

  fix_webroot_perms
  ok "WordPress downloaded to ${WEBROOT}"
}

# Migrate an existing site from a cPanel / DirectAdmin backup (or a plain
# files-archive + .sql dump). The archive is unpacked, the WordPress files and
# the database dump are located automatically wherever they sit inside the
# backup, the dump is imported into the fresh random database, wp-config.php is
# re-pointed at the new credentials, and every occurrence of the old site URL
# is rewritten to the new domain with `wp search-replace`.
migrate_from_backup() {
  step "8/9  Restoring from backup / بازگردانی از بکاپ"
  WEBROOT="/var/www/${DOMAIN}"
  ensure_wp_cli

  local work src xdir wp_root sql_file
  work="$(mktemp -d -p /var/tmp wpmig.XXXXXX)"
  xdir="${work}/extracted"
  mkdir -p "${xdir}"

  # 1) Obtain the archive (download it, or use a local path).
  if [[ "${BACKUP_SRC}" =~ ^https?:// ]]; then
    log "Downloading backup ..."
    wget -q --show-progress "${BACKUP_SRC}" -O "${work}/backup" \
      || { err "Failed to download the backup from ${BACKUP_SRC}"; exit 1; }
    src="${work}/backup"
  else
    src="${BACKUP_SRC}"
  fi

  # 2) Extract (tar.gz / tgz / tar / zip; fall back by trying both).
  log "Extracting the backup ..."
  case "${src}" in
    *.zip)              unzip -q -o "${src}" -d "${xdir}" ;;
    *.tar.gz|*.tgz)     tar -xzf "${src}" -C "${xdir}" ;;
    *.tar)              tar -xf  "${src}" -C "${xdir}" ;;
    *) tar -xzf "${src}" -C "${xdir}" 2>/dev/null \
         || unzip -q -o "${src}" -d "${xdir}" 2>/dev/null \
         || { err "Unknown archive format: ${src}"; exit 1; } ;;
  esac

  # 3) Locate the WordPress root anywhere in the tree (wp-load.php lives there).
  #    Works for cPanel (homedir/public_html) and DirectAdmin (domains/<d>/public_html).
  local wp_load
  wp_load="$(find "${xdir}" -type f -name wp-load.php 2>/dev/null | head -n1 || true)"
  if [[ -z "${wp_load}" ]]; then
    err "No WordPress installation found inside the backup (wp-load.php missing)."
    err "داخل بکاپ نصب وردپرسی پیدا نشد."
    rm -rf "${work}"; exit 1
  fi
  wp_root="$(dirname "${wp_load}")"
  ok "Found WordPress files at: ${wp_root#${xdir}/}"

  # 4) Locate a database dump that contains WordPress tables.
  #    cPanel: mysql/<db>.sql   |   DirectAdmin: backup/<user>_<db>.sql[.gz]
  local f
  while IFS= read -r f; do
    # Read via process substitution so grep's early exit can't SIGPIPE-fail
    # the pipeline under `set -o pipefail`.
    if [[ "${f}" == *.gz ]]; then
      grep -qiE '(CREATE TABLE|INSERT INTO)[^;]*options' < <(zcat "${f}" 2>/dev/null) \
        && { sql_file="${f}"; break; }
    else
      grep -qiE '(CREATE TABLE|INSERT INTO)[^;]*options' "${f}" \
        && { sql_file="${f}"; break; }
    fi
  done < <(find "${xdir}" -type f \( -iname '*.sql' -o -iname '*.sql.gz' \) 2>/dev/null)

  if [[ -z "${sql_file:-}" ]]; then
    err "No WordPress database dump (*.sql) was found inside the backup."
    err "فایل دیتابیس (*.sql) داخل بکاپ پیدا نشد."
    rm -rf "${work}"; exit 1
  fi
  ok "Found database dump at: ${sql_file#${xdir}/}"

  # 5) Move the files into the web root.
  log "Copying site files into ${WEBROOT} ..."
  mkdir -p "${WEBROOT}"
  cp -a "${wp_root}/." "${WEBROOT}/"

  # 6) Import the dump into the fresh random database (as root, via socket).
  #    Strip any USE/CREATE DATABASE lines so it always lands in our DB.
  log "Importing the database ..."
  if [[ "${sql_file}" == *.gz ]]; then
    zcat "${sql_file}" | sed '/^\s*USE\s/Id; /^\s*CREATE DATABASE/Id' \
      | mysql --max_allowed_packet=512M "${DB_NAME}"
  else
    sed '/^\s*USE\s/Id; /^\s*CREATE DATABASE/Id' "${sql_file}" \
      | mysql --max_allowed_packet=512M "${DB_NAME}"
  fi
  ok "Database imported."

  # 7) Point wp-config.php at the NEW database credentials (keep everything
  #    else: salts, table prefix, custom constants). Create one if missing.
  if [[ -f "${WEBROOT}/wp-config.php" ]]; then
    wp config set DB_NAME     "${DB_NAME}" --path="${WEBROOT}" --allow-root --quiet
    wp config set DB_USER     "${DB_USER}" --path="${WEBROOT}" --allow-root --quiet
    wp config set DB_PASSWORD "${DB_PASS}" --path="${WEBROOT}" --allow-root --quiet
    wp config set DB_HOST     "localhost"  --path="${WEBROOT}" --allow-root --quiet
  else
    # Detect the table prefix from the dump (e.g. wp_ from wp_options).
    # Trailing `|| true` keeps a SIGPIPE from `head` (with pipefail) from
    # aborting the script during this assignment.
    local pref
    pref="$( { [[ "${sql_file}" == *.gz ]] && zcat "${sql_file}" || cat "${sql_file}"; } 2>/dev/null \
      | grep -oiE 'CREATE TABLE `?[a-z0-9_]+options`?' | head -n1 \
      | grep -oiE '[a-z0-9_]+options' | head -n1 \
      | sed -E 's/options$//I' || true )"
    [[ -z "${pref}" ]] && pref="wp_"
    wp config create --path="${WEBROOT}" --allow-root --force \
      --dbname="${DB_NAME}" --dbuser="${DB_USER}" \
      --dbpass="${DB_PASS}" --dbhost="localhost" --dbprefix="${pref}"
  fi
  WP_PREFIX="$(wp config get table_prefix --path="${WEBROOT}" --allow-root 2>/dev/null || echo 'wp_')"

  fix_webroot_perms   # wp-config exists now, so it gets chmod 640

  # 8) Rewrite the old site URL to the new domain across all tables.
  local new_url old_url old_host
  new_url="http://${DOMAIN}"; [[ "${INSTALL_SSL}" == "yes" ]] && new_url="https://${DOMAIN}"
  old_url="$(wp option get siteurl --path="${WEBROOT}" --allow-root 2>/dev/null || true)"
  if [[ -n "${old_url}" && "${old_url}" != "${new_url}" ]]; then
    log "Rewriting URLs: ${old_url}  ->  ${new_url}"
    wp search-replace "${old_url}" "${new_url}" \
      --all-tables --skip-columns=guid --path="${WEBROOT}" --allow-root --quiet || true
    # Also swap the bare hostname (covers hard-coded, scheme-less references).
    old_host="${old_url#*://}"; old_host="${old_host%%/*}"
    if [[ -n "${old_host}" && "${old_host}" != "${DOMAIN}" ]]; then
      wp search-replace "${old_host}" "${DOMAIN}" \
        --all-tables --skip-columns=guid --path="${WEBROOT}" --allow-root --quiet || true
    fi
    wp option update home "${new_url}" --path="${WEBROOT}" --allow-root --quiet || true
    wp option update siteurl "${new_url}" --path="${WEBROOT}" --allow-root --quiet || true
  fi

  wp cache flush --path="${WEBROOT}" --allow-root --quiet 2>/dev/null || true
  rm -rf "${work}"
  ok "Site restored to ${WEBROOT} (prefix: ${WP_PREFIX})."
}

configure_nginx_site() {
  step "9/9  Configuring the Nginx site / پیکربندی سایت Nginx"
  local conf="/etc/nginx/sites-available/${DOMAIN}"

  cat > "${conf}" <<-NGINX
	server {
	    listen 80;
	    listen [::]:80;
	    server_name ${DOMAIN} www.${DOMAIN};

	    root ${WEBROOT};
	    index index.php index.html index.htm;

	    client_max_body_size 128M;

	    # --- Security hardening ---
	    # Never serve wp-config.php or hidden files (except ACME challenges).
	    location = /wp-config.php { deny all; }
	    location ~* /\.(?!well-known).* { deny all; }
	    # Block PHP execution inside the uploads directory (common attack path).
	    location ~* /wp-content/uploads/.*\.php\$ { deny all; }

	    location / {
	        try_files \$uri \$uri/ /index.php?\$args;
	    }

	    location ~ \.php\$ {
	        include snippets/fastcgi-php.conf;
	        fastcgi_pass unix:/run/php/php${PHP_VERSION}-fpm.sock;
	    }

	    location = /favicon.ico { log_not_found off; access_log off; }
	    location = /robots.txt  { allow all; log_not_found off; access_log off; }
	    location ~* \.(js|css|png|jpg|jpeg|gif|ico|svg|webp|woff2?)\$ {
	        expires max;
	        log_not_found off;
	    }
	}
	NGINX

  ln -sf "${conf}" "/etc/nginx/sites-enabled/${DOMAIN}"
  rm -f /etc/nginx/sites-enabled/default
  nginx -t
  systemctl reload nginx
  ok "Nginx site configured for ${DOMAIN}."

  if [[ "${INSTALL_SSL}" == "yes" ]]; then
    step "Issuing SSL certificate / صدور گواهی SSL"
    apt-get install -y certbot python3-certbot-nginx
    if certbot --nginx -d "${DOMAIN}" -d "www.${DOMAIN}" \
        --non-interactive --agree-tos -m "${SSL_EMAIL}" --redirect; then
      ok "SSL certificate installed."
    else
      warn "Certbot failed (DNS may not point to this server yet)."
      warn "You can retry later with: certbot --nginx -d ${DOMAIN} -d www.${DOMAIN}"
    fi
  elif [[ "${BEHIND_CDN}" == "yes" ]]; then
    log "Skipped server SSL (domain is behind a CDN). Enable SSL in your CDN panel."
    log "نصب SSL روی سرور رد شد؛ SSL را از پنل CDN خود فعال کنید."
  fi
}

harden_system() {
  step "Security hardening / سخت‌سازی امنیتی"

  # --- Firewall (UFW) ---------------------------------------------------
  # Detect the SSH port from the active session (falls back to sshd_config,
  # then 22) and allow it BEFORE enabling the firewall, so we never lock the
  # administrator out.
  local ssh_port=""
  [[ -n "${SSH_CONNECTION:-}" ]] && ssh_port="$(awk '{print $NF}' <<<"${SSH_CONNECTION}")"
  if [[ -z "${ssh_port}" ]]; then
    ssh_port="$(grep -oiE '^[[:space:]]*Port[[:space:]]+[0-9]+' /etc/ssh/sshd_config 2>/dev/null \
      | grep -oE '[0-9]+' | head -n1)"
  fi
  [[ -z "${ssh_port}" ]] && ssh_port=22

  if command -v ufw >/dev/null 2>&1; then
    ufw allow "${ssh_port}/tcp" >/dev/null 2>&1 || true
    ufw allow OpenSSH        >/dev/null 2>&1 || true
    ufw allow 'Nginx Full'   >/dev/null 2>&1 || true
    ufw --force enable       >/dev/null 2>&1 || true
    ok "Firewall enabled (SSH port ${ssh_port} + HTTP/HTTPS allowed)."
  else
    warn "ufw not available; firewall not enabled."
  fi

  # --- Fail2ban (SSH brute-force protection) ----------------------------
  if apt-get install -y fail2ban >/dev/null 2>&1; then
    printf '[sshd]\nenabled = true\n' > /etc/fail2ban/jail.local
    systemctl enable --now fail2ban >/dev/null 2>&1 || true
    ok "Fail2ban active (SSH brute-force protection)."
  else
    warn "Fail2ban could not be installed; skipping."
  fi

  # --- Automatic security updates ---------------------------------------
  if apt-get install -y unattended-upgrades >/dev/null 2>&1; then
    cat > /etc/apt/apt.conf.d/20auto-upgrades <<-EOF
		APT::Periodic::Update-Package-Lists "1";
		APT::Periodic::Unattended-Upgrade "1";
	EOF
    systemctl enable --now unattended-upgrades >/dev/null 2>&1 || true
    ok "Automatic security updates enabled."
  else
    warn "unattended-upgrades could not be installed; skipping."
  fi
}

setup_speed_pack() {
  step "Speed pack (Redis, OPcache, gzip) / بسته‌ی سرعت"

  # Redis server + PHP extension (object cache backend, bound to localhost).
  if apt-get install -y redis-server "php${PHP_VERSION}-redis" >/dev/null 2>&1; then
    systemctl enable --now redis-server >/dev/null 2>&1 || true
    ok "Redis installed and running (127.0.0.1:6379)."
  else
    warn "Redis could not be installed; skipping object cache."
  fi

  # OPcache tuning for both SAPIs (pure speed win, no staleness risk).
  local sapi
  for sapi in fpm cli; do
    cat > "/etc/php/${PHP_VERSION}/${sapi}/conf.d/98-opcache.ini" <<-INI
		opcache.enable=1
		opcache.enable_cli=0
		opcache.memory_consumption=192
		opcache.interned_strings_buffer=16
		opcache.max_accelerated_files=20000
		opcache.revalidate_freq=2
		opcache.fast_shutdown=1
	INI
  done
  systemctl restart "php${PHP_VERSION}-fpm" >/dev/null 2>&1 || true

  # Nginx gzip + bigger FastCGI buffers. `gzip on;` is already active in the
  # stock nginx.conf, so we only add the sub-settings (no duplicate directive).
  cat > /etc/nginx/conf.d/10-performance.conf <<'NG'
# One-Click WordPress performance tuning
gzip_vary on;
gzip_proxied any;
gzip_comp_level 5;
gzip_min_length 256;
gzip_types text/plain text/css text/xml application/json application/javascript application/xml application/rss+xml text/javascript image/svg+xml font/woff2;
fastcgi_buffers 16 16k;
fastcgi_buffer_size 32k;
NG
  if nginx -t >/dev/null 2>&1; then
    systemctl reload nginx >/dev/null 2>&1 || true
    ok "Nginx gzip compression enabled."
  else
    warn "Performance nginx config was rejected; reverting it."
    rm -f /etc/nginx/conf.d/10-performance.conf
  fi

  # When the site is already live (migration), install & enable the Redis
  # Object Cache plugin. For a fresh install the user activates it later.
  if [[ "${INSTALL_MODE}" == "migrate" && -f "${WEBROOT}/wp-config.php" ]]; then
    if command -v redis-cli >/dev/null && redis-cli ping >/dev/null 2>&1; then
      wp plugin install redis-cache --activate \
        --path="${WEBROOT}" --allow-root --quiet 2>/dev/null || true
      wp redis enable --path="${WEBROOT}" --allow-root 2>/dev/null || true
      ok "Redis object cache enabled for the site."
    fi
  fi
}

setup_backups() {
  step "Automatic backups / بکاپ خودکار"

  # Per-site config read by wp-backup / wp-restore / wpctl.
  cat > /etc/one-click-wp.conf <<-EOF
		# One-Click WordPress site configuration
		DOMAIN="${DOMAIN}"
		WEBROOT="${WEBROOT}"
		PHP_VERSION="${PHP_VERSION}"
		BACKUP_DIR="/root/backups"
		BACKUP_KEEP="7"
	EOF
  chmod 600 /etc/one-click-wp.conf

  # --- wp-backup: dump the DB + tar the files, with rotation --------------
  cat > /usr/local/bin/wp-backup <<'BKP'
#!/usr/bin/env bash
# Back up the WordPress database and files. Run by cron daily, or manually.
set -euo pipefail
export PATH="/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
CONF=/etc/one-click-wp.conf
[[ -r "$CONF" ]] || { echo "Missing $CONF"; exit 1; }
# shellcheck disable=SC1090
. "$CONF"
ts="$(date +%Y%m%d-%H%M%S)"
dest="${BACKUP_DIR}/${DOMAIN}"
mkdir -p "$dest"

# Database (only once WordPress is configured, i.e. wp-config.php exists).
if [[ -f "${WEBROOT}/wp-config.php" ]]; then
  tmp="$(mktemp)"
  if wp db export "$tmp" --path="$WEBROOT" --allow-root >/dev/null 2>&1; then
    gzip -c "$tmp" > "${dest}/db-${ts}.sql.gz"
  else
    echo "WARNING: database export failed"
  fi
  rm -f "$tmp"
fi

# Files.
tar -czf "${dest}/files-${ts}.tar.gz" -C "$(dirname "$WEBROOT")" "$(basename "$WEBROOT")"

# Rotation: keep the newest BACKUP_KEEP of each kind. Sort by NAME (the
# filenames embed a sortable timestamp) so it doesn't depend on mtime.
ls -1 "${dest}"/db-*.sql.gz    2>/dev/null | sort | head -n -"${BACKUP_KEEP}" | xargs -r rm -f || true
ls -1 "${dest}"/files-*.tar.gz 2>/dev/null | sort | head -n -"${BACKUP_KEEP}" | xargs -r rm -f || true
echo "[$(date)] Backup complete: ${dest} (kept last ${BACKUP_KEEP})"
BKP
  chmod +x /usr/local/bin/wp-backup

  # --- wp-restore: restore files + DB from a chosen backup ---------------
  cat > /usr/local/bin/wp-restore <<'RST'
#!/usr/bin/env bash
# Restore the WordPress site from a backup. Usage: wp-restore [TIMESTAMP]
set -euo pipefail
export PATH="/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
CONF=/etc/one-click-wp.conf
[[ -r "$CONF" ]] || { echo "Missing $CONF"; exit 1; }
# shellcheck disable=SC1090
. "$CONF"
dest="${BACKUP_DIR}/${DOMAIN}"
ts="${1:-}"
if [[ -z "$ts" ]]; then
  echo "Available backups for ${DOMAIN}:"
  ls -1 "${dest}"/files-*.tar.gz 2>/dev/null | sed 's#.*/files-##; s#\.tar\.gz##' || true
  printf 'Timestamp to restore (blank = latest): '
  read -r ts </dev/tty || true
fi
[[ -z "$ts" ]] && ts="$(ls -1 "${dest}"/files-*.tar.gz 2>/dev/null | sort | tail -n1 | sed 's#.*/files-##; s#\.tar\.gz##')"
files="${dest}/files-${ts}.tar.gz"
db="${dest}/db-${ts}.sql.gz"
[[ -f "$files" ]] || { echo "Backup not found: $files"; exit 1; }
echo "Restoring ${ts} ..."
tar -xzf "$files" -C "$(dirname "$WEBROOT")"
chown -R www-data:www-data "$WEBROOT"
if [[ -f "$db" && -f "${WEBROOT}/wp-config.php" ]]; then
  tmp="$(mktemp)"; zcat "$db" > "$tmp"
  wp db import "$tmp" --path="$WEBROOT" --allow-root   # dump includes DROP TABLE
  rm -f "$tmp"
fi
wp cache flush --path="$WEBROOT" --allow-root 2>/dev/null || true
echo "Restore complete (${ts})."
RST
  chmod +x /usr/local/bin/wp-restore

  # Daily cron at 03:30.
  cat > /etc/cron.d/one-click-wp-backup <<-EOF
		# One-Click WordPress daily backup
		30 3 * * * root /usr/local/bin/wp-backup >> /var/log/wp-backup.log 2>&1
	EOF
  chmod 644 /etc/cron.d/one-click-wp-backup

  # Take an initial backup now if the site already has data (migration).
  if [[ "${INSTALL_MODE}" == "migrate" && -f "${WEBROOT}/wp-config.php" ]]; then
    /usr/local/bin/wp-backup >/dev/null 2>&1 \
      && ok "Initial backup created in /root/backups." \
      || warn "Initial backup skipped."
  fi
  ok "Daily backups scheduled (03:30) → /root/backups   (use: wp-backup / wp-restore)."
}

# Install `wpctl`: a friendly management menu (and CLI) so a non-expert can run
# common tasks without memorising commands.
install_wpctl() {
  step "Management command / دستور مدیریتی wpctl"
  cat > /usr/local/bin/wpctl <<'WPCTL'
#!/usr/bin/env bash
# wpctl — simple management menu for your One-Click WordPress server.
set -uo pipefail
export PATH="/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

CONF=/etc/one-click-wp.conf
[[ -r "$CONF" ]] || { echo "Missing $CONF — is this a One-Click WordPress server?"; exit 1; }
# shellcheck disable=SC1090
. "$CONF"
PHP_VERSION="${PHP_VERSION:-$(ls /etc/php 2>/dev/null | sort -V | tail -n1)}"
if [[ -d "/etc/letsencrypt/live/${DOMAIN}" ]]; then SCHEME=https; else SCHEME=http; fi
URL="${SCHEME}://${DOMAIN}"

C_R=$'\033[0m'; C_G=$'\033[1;32m'; C_Y=$'\033[1;33m'; C_C=$'\033[1;36m'; C_RED=$'\033[1;31m'
[[ -t 1 ]] || { C_R=""; C_G=""; C_Y=""; C_C=""; C_RED=""; }

need_root(){ [[ ${EUID} -eq 0 ]] || { echo "Please run as root (sudo wpctl)"; exit 1; }; }
WP(){ wp "$@" --path="$WEBROOT" --allow-root; }
have_wp(){ [[ -f "$WEBROOT/wp-config.php" ]]; }
pause(){ printf '\n%sPress Enter to continue…%s ' "$C_Y" "$C_R"; read -r _ </dev/tty || true; }

status(){
  echo "${C_C}== Status / وضعیت ==${C_R}"
  echo "Site: $URL"
  local svc
  for svc in nginx "php${PHP_VERSION}-fpm" mariadb redis-server fail2ban; do
    if systemctl is-active --quiet "$svc" 2>/dev/null; then
      printf '  %s[running]%s %s\n' "$C_G" "$C_R" "$svc"
    else
      printf '  %s[stopped]%s %s\n' "$C_RED" "$C_R" "$svc"
    fi
  done
  local code; code=$(curl -s -o /dev/null -w '%{http_code}' -m 10 "$URL" 2>/dev/null || echo "---")
  echo "HTTP response: $code"
  df -h / | awk 'NR==2{printf "Disk: %s free of %s (%s used)\n",$4,$2,$5}'
  free -h 2>/dev/null | awk '/Mem:/{printf "RAM: %s used / %s total\n",$3,$2}'
  have_wp && echo "WordPress: $(WP core version 2>/dev/null || echo '?')"
}

do_update(){
  echo "${C_C}== Update WordPress, plugins & themes ==${C_R}"
  have_wp || { echo "WordPress isn't set up yet (finish the web installer first)."; return; }
  WP core update || true
  WP core update-db || true
  WP plugin update --all || true
  WP theme update --all || true
  echo "${C_G}Update finished.${C_R}"
}

do_info(){
  echo "${C_C}== Site & login info ==${C_R}"
  echo "Site:  $URL"
  echo "Admin: $URL/wp-admin"
  [[ -f /root/wordpress-credentials.txt ]] && { echo; cat /root/wordpress-credentials.txt; }
}

do_ssl(){
  need_root
  echo "${C_C}== Get / renew SSL ==${C_R}"
  local email; printf 'Email for renewal notices: '; read -r email </dev/tty || true
  apt-get install -y certbot python3-certbot-nginx >/dev/null 2>&1 || true
  if certbot --nginx -d "$DOMAIN" -d "www.$DOMAIN" --non-interactive --agree-tos --redirect -m "$email"; then
    echo "${C_G}SSL installed.${C_R}"
    if have_wp; then
      WP search-replace "http://$DOMAIN" "https://$DOMAIN" --all-tables --skip-columns=guid --quiet || true
      WP option update home "https://$DOMAIN" --quiet || true
      WP option update siteurl "https://$DOMAIN" --quiet || true
      echo "Site URL switched to https."
    fi
  else
    echo "${C_RED}Certbot failed — check the domain's DNS points to this server.${C_R}"
  fi
}

do_upload(){
  need_root
  echo "${C_C}== Change max upload size ==${C_R}"
  local size="${1:-}"
  [[ -z "$size" ]] && { printf 'New upload limit (e.g. 100M, 256M): '; read -r size </dev/tty || true; }
  [[ "$size" =~ ^[0-9]+M$ ]] || { echo "Enter a value like 100M or 256M."; return; }
  local num post; num="${size%M}"; post="$((num+28))M"
  local sapi ini
  for sapi in fpm cli; do
    ini="/etc/php/${PHP_VERSION}/${sapi}/conf.d/99-wordpress.ini"
    [[ -f "$ini" ]] || continue
    sed -i "s/^upload_max_filesize.*/upload_max_filesize = ${size}/" "$ini"
    sed -i "s/^post_max_size.*/post_max_size = ${post}/" "$ini"
  done
  local vhost="/etc/nginx/sites-available/${DOMAIN}"
  [[ -f "$vhost" ]] && sed -i "s/client_max_body_size .*/client_max_body_size ${post};/" "$vhost"
  systemctl restart "php${PHP_VERSION}-fpm" >/dev/null 2>&1 || true
  nginx -t >/dev/null 2>&1 && systemctl reload nginx >/dev/null 2>&1 || true
  echo "${C_G}Upload limit set to ${size} (post ${post}).${C_R}"
}

do_password(){
  need_root
  have_wp || { echo "WordPress isn't set up yet."; return; }
  echo "${C_C}== Admin users ==${C_R}"
  WP user list --role=administrator --fields=ID,user_login,user_email 2>/dev/null || true
  local u; printf "\nUsername to reset (or 'new' to create an admin): "; read -r u </dev/tty || true
  [[ -z "$u" ]] && return
  if [[ "$u" == "new" ]]; then
    local nl ne np
    printf 'New username: '; read -r nl </dev/tty
    printf 'Email: ';        read -r ne </dev/tty
    printf 'Password: ';     read -rs np </dev/tty; echo
    WP user create "$nl" "$ne" --role=administrator --user_pass="$np" && echo "${C_G}Created.${C_R}"
  else
    local np; printf 'New password: '; read -rs np </dev/tty; echo
    WP user update "$u" --user_pass="$np" && echo "${C_G}Password updated.${C_R}"
  fi
}

do_flush(){
  echo "${C_C}== Flush caches ==${C_R}"
  if have_wp; then WP cache flush 2>/dev/null || true; WP redis flush 2>/dev/null || true; fi
  systemctl reload "php${PHP_VERSION}-fpm" >/dev/null 2>&1 || true
  echo "${C_G}Caches flushed.${C_R}"
}

do_maint(){
  have_wp || { echo "WordPress isn't set up yet."; return; }
  local m="${1:-}"
  [[ -z "$m" ]] && { printf 'Maintenance mode (on/off): '; read -r m </dev/tty || true; }
  case "$m" in
    on)  WP maintenance-mode activate   && echo "Maintenance mode ON.";;
    off) WP maintenance-mode deactivate && echo "Maintenance mode OFF.";;
    *)   echo "Use on or off.";;
  esac
}

do_logs(){
  echo "${C_C}== Recent Nginx errors ==${C_R}"
  tail -n 40 /var/log/nginx/error.log 2>/dev/null || echo "(none)"
  echo; echo "${C_C}== Recent PHP-FPM log ==${C_R}"
  tail -n 20 "/var/log/php${PHP_VERSION}-fpm.log" 2>/dev/null || echo "(none)"
}

menu(){
  while true; do
    printf '\n%s── wpctl — %s ──%s\n' "$C_C" "$DOMAIN" "$C_R"
    printf '%s\n' \
      "  1) Status / health        وضعیت سرور" \
      "  2) Backup now             بکاپ فوری" \
      "  3) Restore a backup       بازگردانی" \
      "  4) Update WP + plugins    آپدیت وردپرس و افزونه‌ها" \
      "  5) Site & login info      اطلاعات سایت و ورود" \
      "  6) Get / renew SSL        دریافت/تمدید SSL" \
      "  7) Change upload size     تغییر سقف آپلود" \
      "  8) Admin password / user  رمز یا کاربر مدیر" \
      "  9) Flush caches           پاک‌کردن کش" \
      " 10) Maintenance mode       حالت تعمیر" \
      " 11) View error logs        مشاهده لاگ‌ها" \
      "  0) Quit                   خروج"
    printf '%sChoose:%s ' "$C_Y" "$C_R"; read -r c </dev/tty || break
    case "$c" in
      1) status;; 2) wp-backup;; 3) wp-restore;; 4) do_update;; 5) do_info;;
      6) do_ssl;; 7) do_upload;; 8) do_password;; 9) do_flush;;
      10) do_maint;; 11) do_logs;; 0|q|Q) exit 0;;
      *) echo "Invalid choice.";;
    esac
    pause
  done
}

case "${1:-menu}" in
  menu|"")     menu;;
  status)      status;;
  backup)      wp-backup;;
  restore)     shift; wp-restore "$@";;
  update)      do_update;;
  info)        do_info;;
  ssl)         do_ssl;;
  upload)      shift; do_upload "$@";;
  password)    do_password;;
  flush)       do_flush;;
  maintenance) shift; do_maint "$@";;
  logs)        do_logs;;
  -h|--help|help)
    echo "wpctl — manage your WordPress server"
    echo "Usage: wpctl [status|backup|restore|update|info|ssl|upload <size>|password|flush|maintenance <on|off>|logs]"
    echo "Run 'wpctl' with no arguments for the interactive menu.";;
  *) echo "Unknown command: $1 (try: wpctl help)"; exit 1;;
esac
WPCTL
  chmod +x /usr/local/bin/wpctl
  ok "Management command installed → run: wpctl"
}

save_credentials() {
  local scheme="http"
  [[ "${INSTALL_SSL}" == "yes" ]] && scheme="https"

  umask 077
  if [[ "${INSTALL_MODE}" == "migrate" ]]; then
    cat > "${CRED_FILE}" <<-EOF
			=============== WordPress Migration (restored) ===============
			Date            : $(date)
			Site URL        : ${scheme}://${DOMAIN}
			Admin panel     : ${scheme}://${DOMAIN}/wp-admin
			Web root        : ${WEBROOT}

			Log in with the SAME username/password as on your old host.
			با همان یوزر/رمز مدیریت سایت قبلی وارد شوید.

			Backups        : /root/backups   (wp-backup / wp-restore, daily 03:30)

			--- New database connection (already written to wp-config.php) ---
			Database name   : ${DB_NAME}
			Username        : ${DB_USER}
			Password        : ${DB_PASS}
			Database host   : localhost
			Table prefix    : ${WP_PREFIX}
			=============================================================
		EOF
  else
    cat > "${CRED_FILE}" <<-EOF
			==================== WordPress Install ====================
			Date            : $(date)
			Site URL        : ${scheme}://${DOMAIN}
			Install page    : ${scheme}://${DOMAIN}/wp-admin/install.php
			Admin panel     : ${scheme}://${DOMAIN}/wp-admin
			Web root        : ${WEBROOT}

			--- Database (enter these in the WordPress web installer) ---
			Database name   : ${DB_NAME}
			Username        : ${DB_USER}
			Password        : ${DB_PASS}
			Database host   : localhost
			Table prefix    : wp_

			Backups         : /root/backups   (wp-backup / wp-restore, daily 03:30)
			===========================================================
		EOF
  fi
  chmod 600 "${CRED_FILE}"
}

print_summary() {
  local scheme="http"
  [[ "${INSTALL_SSL}" == "yes" ]] && scheme="https"

  local url="${scheme}://${DOMAIN}"

  printf '\n%s\n' "${C_GREEN}=================================================================${C_RESET}"
  printf '%s\n' "${C_GREEN}  Installation complete!  /  نصب با موفقیت انجام شد!${C_RESET}"
  printf '%s\n\n' "${C_GREEN}=================================================================${C_RESET}"

  if [[ "${INSTALL_MODE}" == "migrate" ]]; then
    printf '%s\n' "${C_GREEN}─────────────────────────────────────────────────────────────────${C_RESET}"
    printf '%s\n' "  👉  Your migrated site is live at:"
    printf '%s\n\n' "  👉  سایت منتقل‌شده‌ی شما اینجا بالا آمده است:"
    printf '        %s\n' "${C_CYAN}${url}${C_RESET}"
    printf '        %s\n' "admin: ${C_CYAN}${url}/wp-admin${C_RESET}"
    printf '%s\n' "${C_GREEN}─────────────────────────────────────────────────────────────────${C_RESET}"
    printf '\n%s\n' "Log in with the SAME username/password you used on your old host."
    printf '%s\n\n' "با همان یوزر و رمز مدیریت سایت قبلی‌تان وارد شوید."
    printf '%s\n' "The new database connection is already written to wp-config.php."
    printf '%s\n\n' "اتصال دیتابیس جدید از قبل در wp-config.php تنظیم شده است."
  else
    printf '%s\n' "${C_GREEN}─────────────────────────────────────────────────────────────────${C_RESET}"
    printf '%s\n' "  👉  Open this address in your browser to install WordPress:"
    printf '%s\n\n' "  👉  این آدرس را در مرورگر باز کنید تا وردپرس نصب شود:"
    printf '        %s\n' "${C_CYAN}${url}/wp-admin/install.php${C_RESET}"
    printf '%s\n' "${C_GREEN}─────────────────────────────────────────────────────────────────${C_RESET}"
    printf '\n%s\n' "(You can also just open ${C_CYAN}${url}${C_RESET} — it redirects to the installer.)"
    printf '%s\n\n' "(می‌توانید ${C_CYAN}${url}${C_RESET} را هم باز کنید؛ خودش به صفحه‌ی نصب می‌رود.)"

    printf '%s\n' "On the first screen choose your LANGUAGE, then enter these DB details:"
    printf '%s\n\n' "در صفحه‌ی اول زبان را انتخاب کنید، سپس اطلاعات دیتابیس زیر را وارد کنید:"
    printf '    %-16s %s\n' "Database name:" "${DB_NAME}"
    printf '    %-16s %s\n' "Username:"      "${DB_USER}"
    printf '    %-16s %s\n' "Password:"      "${DB_PASS}"
    printf '    %-16s %s\n' "Database host:" "localhost"
    printf '    %-16s %s\n\n' "Table prefix:" "wp_"

    printf '%s\n' "After finishing, your admin panel will be at: ${C_CYAN}${url}/wp-admin${C_RESET}"
    printf '%s\n\n' "بعد از پایان، پنل مدیریت شما اینجاست: ${C_CYAN}${url}/wp-admin${C_RESET}"
  fi

  printf '%s\n' "${C_YELLOW}Details are also saved (root-only) to: ${CRED_FILE}${C_RESET}"
  printf '%s\n' "${C_YELLOW}این اطلاعات در فایل بالا هم ذخیره شده است (فقط برای root).${C_RESET}"

  printf '\n%s\n' "Security enabled: UFW firewall, Fail2ban, automatic security updates."
  printf '%s\n' "امنیت فعال شد: فایروال UFW، Fail2ban، و بروزرسانی امنیتی خودکار."

  printf '\n%s\n' "Daily backups → /root/backups   (run ${C_CYAN}wp-backup${C_RESET} anytime, ${C_CYAN}wp-restore${C_RESET} to roll back)."
  printf '%s\n' "بکاپ روزانه → /root/backups   (دستور ${C_CYAN}wp-backup${C_RESET} برای بکاپ فوری و ${C_CYAN}wp-restore${C_RESET} برای بازگردانی)."
  printf '%s\n' "Speed pack: Redis + OPcache + gzip enabled."
  printf '%s\n' "Manage everything with one simple menu — just run: ${C_CYAN}wpctl${C_RESET}"
  printf '%s\n' "همه‌چیز را با یک منوی ساده مدیریت کنید — کافیست بزنید: ${C_CYAN}wpctl${C_RESET}"
  if [[ "${INSTALL_MODE}" != "migrate" ]]; then
    printf '%s\n' "${C_YELLOW}Tip: after finishing setup, install the 'Redis Object Cache' plugin and click Enable for faster DB caching.${C_RESET}"
    printf '%s\n' "${C_YELLOW}نکته: بعد از نصب، افزونه‌ی 'Redis Object Cache' را نصب و فعال کنید تا کش دیتابیس سریع‌تر شود.${C_RESET}"
  fi

  if [[ "${BEHIND_CDN}" == "yes" ]]; then
    printf '\n%s\n' "Note: enable SSL in your CDN panel (ArvanCloud/Cloudflare)."
    printf '%s\n' "نکته: SSL را از پنل CDN خود فعال کنید."
  fi
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
main() {
  printf '%s\n' "${C_CYAN}"
  printf '%s\n' "  One-Click WordPress Install"
  printf '%s\n' "  نصب یک‌کلیکی وردپرس روی Ubuntu"
  printf '%s\n' "${C_RESET}"

  require_root
  require_ubuntu
  collect_input

  update_system
  install_base_packages
  ensure_swap
  install_nginx
  install_php
  install_database
  install_ioncube
  tune_php
  if [[ "${INSTALL_MODE}" == "migrate" ]]; then
    migrate_from_backup
  else
    download_wordpress
  fi
  configure_nginx_site
  setup_speed_pack
  harden_system
  setup_backups
  install_wpctl
  save_credentials
  print_summary
}

main "$@"
