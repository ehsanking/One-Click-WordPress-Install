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
#   - Install PHP 8.1 (php-fpm + extensions)
#   - Install MariaDB and auto-create a random database, user and password
#   - Download & install the correct ionCube Loader and wire it into php.ini
#   - Tune php.ini  (upload 50M, memory_limit 1024M)
#   - Download WordPress so the user can finish the famous web installer
#     (picking the language) using the database credentials we print.
#
# Usage (one line):
#   bash <(curl -fsSL https://raw.githubusercontent.com/ehsanking/One-Click-WordPress-Install/main/install.sh)
#
# Tested on Ubuntu 20.04 / 22.04 / 24.04.

set -euo pipefail

# ---------------------------------------------------------------------------
# Constants & globals
# ---------------------------------------------------------------------------
readonly PHP_VERSION="8.1"
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
}

# ---------------------------------------------------------------------------
# Installation steps
# ---------------------------------------------------------------------------
update_system() {
  step "1/9  Updating & upgrading the system / بروزرسانی سیستم"
  export DEBIAN_FRONTEND=noninteractive
  export NEEDRESTART_MODE=a
  apt-get update -y
  apt-get upgrade -y
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
  # Basic firewall (won't lock anyone out: SSH stays open).
  if command -v ufw >/dev/null; then
    ufw allow OpenSSH >/dev/null 2>&1 || true
    ufw allow 'Nginx Full' >/dev/null 2>&1 || true
  fi
  ok "Nginx installed and running."
}

install_php() {
  step "4/9  Installing PHP ${PHP_VERSION} / نصب PHP ${PHP_VERSION}"
  add-apt-repository -y ppa:ondrej/php
  apt-get update -y
  apt-get install -y \
    "php${PHP_VERSION}-fpm" "php${PHP_VERSION}-cli" "php${PHP_VERSION}-common" \
    "php${PHP_VERSION}-mysql" "php${PHP_VERSION}-curl" "php${PHP_VERSION}-gd" \
    "php${PHP_VERSION}-mbstring" "php${PHP_VERSION}-xml" "php${PHP_VERSION}-zip" \
    "php${PHP_VERSION}-intl" "php${PHP_VERSION}-bcmath" "php${PHP_VERSION}-soap" \
    "php${PHP_VERSION}-imagick" "php${PHP_VERSION}-opcache"
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
  step "7/9  Tuning php.ini (50M uploads, 1GB memory) / تنظیم php.ini"
  local sapi ini_dir
  for sapi in fpm cli; do
    ini_dir="/etc/php/${PHP_VERSION}/${sapi}/conf.d"
    cat > "${ini_dir}/99-wordpress.ini" <<-INI
		; One-Click WordPress Install tuning
		upload_max_filesize = 50M
		post_max_size = 51M
		memory_limit = 1024M
		max_execution_time = 300
		max_input_time = 300
		max_input_vars = 5000
		file_uploads = On
		cgi.fix_pathinfo = 0
	INI
  done
  systemctl restart "php${PHP_VERSION}-fpm"
  ok "php.ini tuned (upload 50M, memory_limit 1024M)."
}

download_wordpress() {
  step "8/9  Downloading WordPress / دانلود وردپرس"
  WEBROOT="/var/www/${DOMAIN}"

  # Install WP-CLI (handy for download and future maintenance).
  if ! command -v wp >/dev/null; then
    curl -fsSL https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar \
      -o /usr/local/bin/wp
    chmod +x /usr/local/bin/wp
  fi

  mkdir -p "${WEBROOT}"
  # Download the latest WordPress core. The language is chosen by the user
  # later, on the first screen of the web installer.
  wp core download --path="${WEBROOT}" --allow-root --force

  # Permissions: web server owns the files; dirs 755, files 644.
  chown -R www-data:www-data "${WEBROOT}"
  find "${WEBROOT}" -type d -exec chmod 755 {} \;
  find "${WEBROOT}" -type f -exec chmod 644 {} \;
  ok "WordPress downloaded to ${WEBROOT}"
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

	    client_max_body_size 50M;

	    location / {
	        try_files \$uri \$uri/ /index.php?\$args;
	    }

	    location ~ \.php\$ {
	        include snippets/fastcgi-php.conf;
	        fastcgi_pass unix:/run/php/php${PHP_VERSION}-fpm.sock;
	    }

	    location ~* /\.(?!well-known).* { deny all; }
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

save_credentials() {
  local scheme="http"
  [[ "${INSTALL_SSL}" == "yes" ]] && scheme="https"

  umask 077
  cat > "${CRED_FILE}" <<-EOF
		==================== WordPress Install ====================
		Date          : $(date)
		Site URL      : ${scheme}://${DOMAIN}
		Web root      : ${WEBROOT}

		--- Database (enter these in the WordPress web installer) ---
		Database name : ${DB_NAME}
		Username      : ${DB_USER}
		Password      : ${DB_PASS}
		Database host : localhost
		Table prefix  : wp_
		===========================================================
	EOF
  chmod 600 "${CRED_FILE}"
}

print_summary() {
  local scheme="http"
  [[ "${INSTALL_SSL}" == "yes" ]] && scheme="https"

  printf '\n%s\n' "${C_GREEN}=================================================================${C_RESET}"
  printf '%s\n' "${C_GREEN}  Installation complete!  /  نصب با موفقیت انجام شد!${C_RESET}"
  printf '%s\n\n' "${C_GREEN}=================================================================${C_RESET}"

  printf '%s\n' "Open this URL in your browser to finish the WordPress install:"
  printf '%s\n\n' "برای تکمیل نصب وردپرس این آدرس را در مرورگر باز کنید:"
  printf '    %s\n\n' "${C_CYAN}${scheme}://${DOMAIN}${C_RESET}"

  printf '%s\n' "On the first screen choose your LANGUAGE, then enter these DB details:"
  printf '%s\n\n' "در صفحه‌ی اول زبان را انتخاب کنید، سپس اطلاعات دیتابیس زیر را وارد کنید:"
  printf '    %-16s %s\n' "Database name:" "${DB_NAME}"
  printf '    %-16s %s\n' "Username:"      "${DB_USER}"
  printf '    %-16s %s\n' "Password:"      "${DB_PASS}"
  printf '    %-16s %s\n' "Database host:" "localhost"
  printf '    %-16s %s\n\n' "Table prefix:" "wp_"

  printf '%s\n' "${C_YELLOW}These credentials are also saved (root-only) to: ${CRED_FILE}${C_RESET}"
  printf '%s\n' "${C_YELLOW}این اطلاعات در فایل بالا هم ذخیره شده است (فقط برای root).${C_RESET}"

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
  download_wordpress
  configure_nginx_site
  save_credentials
  print_summary
}

main "$@"
