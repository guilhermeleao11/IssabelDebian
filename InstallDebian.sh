#!/bin/bash
################################################################################
# Nome do Script: InstallDebian.sh
# Desenvolvedor  : Guilherme Leão - Telium Network
# Data           : 14/08/2025
# Versão         : 1.2
# Objetivo       : Instalar Issabel no Debian 12 com Asterisk 20 LTS, PJSIP+chan_sip,
#                  ODBC/CDR, PHP 7.4 (Sury), Apache + SSL, patches Issabel
################################################################################

set -euo pipefail

# ===== Variáveis =====
ASTERISK_SRC_FILE="${ASTERISK_SRC_FILE:-asterisk-20-current.tar.gz}"
ASTERISK_URL="${ASTERISK_URL:-https://downloads.asterisk.org/pub/telephony/asterisk}"
ASTERISK_URL_CERTIFIED="${ASTERISK_URL_CERTIFIED:-https://downloads.asterisk.org/pub/telephony/asterisk/certified}"

SOURCE_DIR_SCRIPT="${SOURCE_DIR_SCRIPT:-/usr/src/issabel-install}"   # onde estão seus tar/patches
ISSABEL_REPO="${ISSABEL_REPO:-https://github.com/asternic/issabelPBX.git}"

LANGUAGE="${LANGUAGE:-en_EN}"                 # idioma Issabel
ISSABEL_ADMIN_PASSWORD="${ISSABEL_ADMIN_PASSWORD:-Mudar123@}"

LOG_FILE="/var/log/install_issabel.log"

# ===== Funções util =====
log(){ echo -e "\e[1;32m[INFO]\e[0m $*" | tee -a "$LOG_FILE"; }
err(){ echo -e "\e[1;31m[ERRO]\e[0m $*" | tee -a "$LOG_FILE"; exit 1; }

# ===== Pré-checagens =====
[ "$(id -u)" -eq 0 ] || err "Execute como root."
grep -q 'VERSION_CODENAME=bookworm' /etc/os-release || err "Este script é para Debian 12 (bookworm)."
ping -c1 -W2 deb.debian.org &>/dev/null || err "Sem acesso à Internet."

log "Iniciando o script de instalação do Issabel no Debian 12"

# ===== PATH sbin =====
grep -q '/usr/sbin' /etc/bash.bashrc || echo 'export PATH=$PATH:/usr/local/sbin:/usr/sbin' >> /etc/bash.bashrc
echo "$PATH" | grep -q 'sbin' || { err "Error: /usr/sbin não está no PATH (reabra a sessão ou source /etc/bash.bashrc)"; }

# ===== Repositórios Debian: contrib/non-free/non-free-firmware =====
if ! grep -Eq 'deb .* main .*contrib.*non-free' /etc/apt/sources.list; then
  sed -i -E 's/^(deb .* main)(.*)$/\1 contrib non-free non-free-firmware\2/' /etc/apt/sources.list
fi

# ===== Atualização e pacotes básicos =====
log "Atualizando sistema e instalando pacotes básicos..."
apt update && apt -y upgrade
apt install -y apt-transport-https lsb-release ca-certificates wget curl aptitude git \
  apache2 mariadb-server mariadb-client unixodbc odbcinst unixodbc-dev libmariadb-dev \
  cockpit net-tools dialog locales-all libwww-perl mpg123 sox fail2ban cracklib-runtime \
  dnsutils certbot python3-certbot-apache iptables php-pear sngrep git

# ===== PHP 7.4 (Sury) =====
log "Instalando PHP 7.4 (Sury)..."
wget -qO /etc/pki.php.gpg https://packages.sury.org/php/apt.gpg
install -m 644 /etc/pki.php.gpg /etc/apt/trusted.gpg.d/php.gpg
echo "deb https://packages.sury.org/php/ $(lsb_release -sc) main" > /etc/apt/sources.list.d/php.list
apt update
apt-mark hold php8* || true
apt install -y libapache2-mod-php7.4 php7.4-cli php7.4-common php7.4-curl php7.4-json \
  php7.4-mbstring php7.4-mysql php7.4-opcache php7.4-readline php7.4-sqlite3 php7.4-xml

# ===== Ajuste path módulos Asterisk (idempotente) =====
if [ -d /usr/lib/x86_64-linux-gnu/asterisk/modules ] && [ ! -e /usr/lib/asterisk ]; then
  mkdir -p /usr/lib/asterisk
  ln -s /usr/lib/x86_64-linux-gnu/asterisk/modules /usr/lib/asterisk
fi

# ===== Usuário asterisk e diretórios =====
log "Criando usuário e diretórios do Asterisk..."
if ! id -u "asterisk" >/dev/null 2>&1; then
  useradd -r -s /usr/sbin/nologin -d /var/lib/asterisk asterisk
  mkdir -p /var/lib/asterisk
  chown asterisk:asterisk /var/lib/asterisk
fi
mkdir -p /var/{lib,log,spool,run}/asterisk
chown -R asterisk:asterisk /var/{lib,log,spool,run}/asterisk

# ===== Clonar IssabelPBX =====
log "Clonando repositório IssabelPBX..."
cd /usr/src
if [ ! -d /usr/src/issabelPBX ]; then
  git clone "$ISSABEL_REPO"
fi

# ===== Download/extração do Asterisk =====
log "Baixando e preparando fontes do Asterisk..."
cd /usr/src
ASTERISK_SRC_DIR="$(basename "$ASTERISK_SRC_FILE" .tar.gz)"
if ! [ -f "$ASTERISK_SRC_FILE" ]; then
  ASTERISK_URL_DOWNLOAD="$ASTERISK_URL/$ASTERISK_SRC_FILE"
  if echo "$ASTERISK_SRC_FILE" | grep -Fq "certified"; then
    ASTERISK_URL_DOWNLOAD="$ASTERISK_URL_CERTIFIED/$ASTERISK_SRC_FILE"
  fi
  wget -q "$ASTERISK_URL_DOWNLOAD"
fi
rm -rf "/usr/src/${ASTERISK_SRC_DIR}"
mkdir -p "/usr/src/${ASTERISK_SRC_DIR}"
tar xzf "$ASTERISK_SRC_FILE" -C "/usr/src/${ASTERISK_SRC_DIR}" --strip-components=1
cd "/usr/src/${ASTERISK_SRC_DIR}"

# ===== Dependências do Asterisk =====
log "Instalando dependências do Asterisk..."
contrib/scripts/install_prereq install

# ===== Compilar Asterisk + módulos =====
log "Configurando e selecionando módulos..."
./configure
make menuselect.makeopts

# Menuselect (mantém sua intenção original; ajustes: habilitei res_odbc para CDR ODBC e removi kqueue)
menuselect/menuselect \
  --disable-category MENUSELECT_ADDONS \
  --disable app_flash \
  --disable app_skel \
  --disable-category MENUSELECT_CDR \
  --disable-category MENUSELECT_CEL \
  --disable cdr_pgsql \
  --disable cel_pgsql \
  --disable-category MENUSELECT_CHANNELS \
  --enable  chan_iax2 \
  --enable  chan_pjsip \
  --enable  chan_sip \
  --enable  chan_rtp \
  --enable-category MENUSELECT_CODECS \
  --enable-category MENUSELECT_FORMATS \
  --enable-category MENUSELECT_FUNCS \
  --enable-category MENUSELECT_PBX \
  --enable app_macro \
  --enable pbx_config \
  --enable pbx_loopback \
  --enable pbx_spool \
  --enable pbx_realtime \
  --enable res_agi \
  --enable res_ari \
  --enable res_ari_applications \
  --enable res_ari_asterisk \
  --enable res_ari_bridges \
  --enable res_ari_channels \
  --enable res_ari_device_states \
  --enable res_ari_endpoints \
  --enable res_ari_events \
  --enable res_ari_mailboxes \
  --enable res_ari_model \
  --enable res_ari_playbacks \
  --enable res_ari_recordings \
  --enable res_ari_sounds \
  --enable res_clialiases \
  --enable res_clioriginate \
  --enable res_config_curl \
  --enable res_config_odbc \
  --disable res_config_sqlite3 \
  --enable res_convert \
  --enable res_crypto \
  --enable res_curl \
  --enable res_fax \
  --enable res_format_attr_celt \
  --enable res_format_attr_g729 \
  --enable res_format_attr_h263 \
  --enable res_format_attr_h264 \
  --enable res_format_attr_ilbc \
  --enable res_format_attr_opus \
  --enable res_format_attr_silk \
  --enable res_format_attr_siren14 \
  --enable res_format_attr_siren7 \
  --enable res_format_attr_vp8 \
  --enable res_http_media_cache \
  --enable res_http_post \
  --enable res_http_websocket \
  --enable res_limit \
  --enable res_manager_devicestate \
  --enable res_manager_presencestate \
  --enable res_musiconhold \
  --enable res_mutestream \
  --enable res_mwi_devstate \
  --disable res_mwi_external \
  --disable res_mwi_external_ami \
  --enable res_odbc \
  --enable res_odbc_transaction \
  --enable res_parking \
  --enable res_pjproject \
  --enable res_pjsip \
  --enable res_pjsip_acl \
  --enable res_pjsip_authenticator_digest \
  --enable res_pjsip_caller_id \
  --enable res_pjsip_config_wizard \
  --enable res_pjsip_dialog_info_body_generator \
  --enable res_pjsip_diversion \
  --enable res_pjsip_dlg_options \
  --enable res_pjsip_dtmf_info \
  --enable res_pjsip_empty_info \
  --enable res_pjsip_endpoint_identifier_anonymous \
  --enable res_pjsip_endpoint_identifier_ip \
  --enable res_pjsip_endpoint_identifier_user \
  --enable res_pjsip_exten_state \
  --enable res_pjsip_header_funcs \
  --enable res_pjsip_logger \
  --enable res_pjsip_messaging \
  --enable res_pjsip_mwi \
  --enable res_pjsip_mwi_body_generator \
  --enable res_pjsip_nat \
  --enable res_pjsip_notify \
  --enable res_pjsip_one_touch_record_info \
  --enable res_pjsip_outbound_authenticator_digest \
  --enable res_pjsip_outbound_publish \
  --enable res_pjsip_outbound_registration \
  --enable res_pjsip_path \
  --enable res_pjsip_pidf_body_generator \
  --enable res_pjsip_pidf_digium_body_supplement \
  --enable res_pjsip_pidf_eyebeam_body_supplement \
  --enable res_pjsip_publish_asterisk \
  --enable res_pjsip_pubsub \
  --enable res_pjsip_refer \
  --enable res_pjsip_registrar \
  --enable res_pjsip_rfc3326 \
  --enable res_pjsip_sdp_rtp \
  --enable res_pjsip_send_to_voicemail \
  --enable res_pjsip_session \
  --enable res_pjsip_sips_contact \
  --enable res_pjsip_t38 \
  --enable res_pjsip_transport_websocket \
  --enable res_pjsip_xpidf_body_generator \
  --enable res_realtime \
  --enable res_resolver_unbound \
  --enable res_rtp_asterisk \
  --enable res_rtp_multicast \
  --enable res_security_log \
  --enable res_sorcery_astdb \
  --enable res_sorcery_config \
  --enable res_sorcery_memory \
  --enable res_sorcery_memory_cache \
  --enable res_sorcery_realtime \
  --enable res_speech \
  --enable res_srtp \
  --enable res_stasis \
  --enable res_stasis_answer \
  --enable res_stasis_device_state \
  --enable res_stasis_playback \
  --enable res_stasis_recording \
  --enable res_stasis_snoop \
  --enable res_stasis_test \
  --enable res_stun_monitor \
  --enable res_timing_dahdi \
  --enable res_timing_timerfd \
  --disable res_ael_share \
  --disable res_calendar \
  --disable res_calendar_caldav \
  --disable res_calendar_ews \
  --disable res_calendar_exchange \
  --disable res_calendar_icalendar \
  --disable res_chan_stats \
  --enable res_config_pgsql \
  --disable res_corosync \
  --disable res_endpoint_stats \
  --disable res_fax_spandsp \
  --enable res_hep \
  --enable res_hep_pjsip \
  --enable res_hep_rtcp \
  --disable res_phoneprov \
  --disable res_pjsip_history \
  --disable res_pjsip_phoneprov_provider \
  --disable res_pktccops \
  --disable res_remb_modifier \
  --disable res_smdi \
  --disable res_snmp \
  --disable res_statsd \
  --disable res_timing_pthread \
  --disable res_adsi \
  --enable res_config_sqlite3 \
  --disable res_monitor \
  --disable res_digium_phone \
  --disable res_stasis_mailbox \
  --enable cdr_adaptive_odbc \
  --enable cdr_custom \
  --enable cdr_manager  \
  --enable cdr_csv \
  menuselect.makeopts

log "Compilando e instalando Asterisk..."
make -j"$(nproc)"
make install

# ===== Service do Asterisk (systemd) =====
log "Configurando serviço systemd do Asterisk..."
cat > /lib/systemd/system/asterisk.service <<'EOF'
[Unit]
Description=LSB: Asterisk PBX
After=network-online.target postgresql.service
Wants=network-online.target
Conflicts=shutdown.target

[Service]
Type=simple
Environment=HOME=/var/lib/asterisk
WorkingDirectory=/var/lib/asterisk
ExecStart=/usr/sbin/asterisk -U asterisk -G asterisk -mqf -C /etc/asterisk/asterisk.conf
ExecReload=/usr/sbin/asterisk -rx 'core reload'
LimitCORE=infinity
LimitNOFILE=infinity
LimitNPROC=infinity
LimitMEMLOCK=infinity
Restart=on-failure
RestartSec=4
StandardOutput=null
PrivateTmp=true

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload

# ===== Arquivos base do Asterisk (se existirem no repositório interno) =====
if [ -f "$SOURCE_DIR_SCRIPT/asterisk/asterisk_issabel.tar.gz" ]; then
  log "Extraindo base de configs do Asterisk do pacote interno..."
  tar xzf "$SOURCE_DIR_SCRIPT/asterisk/asterisk_issabel.tar.gz" -C /etc
fi
# corrigindo typo do script original
rm -f /etc/asterisk/stir_shaken.conf || true

# ===== Permissões Asterisk =====
chown -R asterisk:asterisk /etc/asterisk /var/run/asterisk /var/log/asterisk /var/lib/asterisk

# ===== Apache: redirect para /admin =====
if [ -f /var/www/html/index.html ]; then
  mv /var/www/html/index.html /var/www/html/index.html.bak
fi
cat > /var/www/html/index.html <<'EOF'
<html><head><meta http-equiv="refresh" content="0; url=/admin"></head><body></body></html>
EOF

# ===== Apache: envvars, diretórios, módulos e SSL =====
sed -i -e "s/^export APACHE_RUN_USER=.*/export APACHE_RUN_USER=asterisk/" /etc/apache2/envvars
sed -i -e "s/^export APACHE_RUN_GROUP=.*/export APACHE_RUN_GROUP=asterisk/" /etc/apache2/envvars

cat > /etc/apache2/conf-available/pbxapi.conf <<'EOF'
<Directory /var/www/html/pbxapi>
    AllowOverride All
</Directory>
EOF
ln -sf /etc/apache2/conf-available/pbxapi.conf /etc/apache2/conf-enabled/pbxapi.conf
a2enmod rewrite ssl
ln -sf /etc/apache2/sites-available/default-ssl.conf /etc/apache2/sites-enabled/default-ssl.conf

# ===== ODBC (driver + DSNs) =====
log "Configurando ODBC para CDR..."
# Preferir pacote oficial do Debian 12 (mais estável)
apt install -y odbc-mariadb || true

# Determinar path do driver
ODBC_DRIVER_SO="$(ldconfig -p | awk '/libmaodbc\.so/ {print $4; exit}')"
if [ -z "${ODBC_DRIVER_SO:-}" ]; then
  # Fallback manual (mantém sua lógica original caso precise)
  cd /usr/src
  DLFILE=""
  if [ -f /etc/debian_version ]; then
    # Melhor tentativa genérica (evita URLs com IDs fixos que expiram)
    DLFILE="https://downloads.mariadb.com/Connectors/odbc/connector-odbc-3.1.18/mariadb-connector-odbc-3.1.18-debian-buster-amd64.tar.gz"
  fi
  if [ -n "$DLFILE" ]; then
    FILENAME=$(basename "$DLFILE")
    rm -f "$FILENAME"
    wget -q "$DLFILE" || true
    tar xzf "$FILENAME" || true
    FOUND_SO="$(find /usr/src -name libmaodbc.so | head -n1 || true)"
    if [ -n "$FOUND_SO" ]; then
      cp "$FOUND_SO" /usr/local/lib/
      ODBC_DRIVER_SO="/usr/local/lib/libmaodbc.so"
      ldconfig
    fi
  fi
fi

# odbcinst.ini
if [ -n "${ODBC_DRIVER_SO:-}" ]; then
cat > /etc/odbcinst.ini <<EOF
[MySQL ODBC 8.0 Unicode Driver]
Driver=${ODBC_DRIVER_SO}
UsageCount=1

[MySQL ODBC 8.0 ANSI Driver]
Driver=${ODBC_DRIVER_SO}
UsageCount=1
EOF
fi

# odbc.ini (DSNs)
cat > /etc/odbc.ini <<'EOF'
[MySQL-asteriskcdrdb]
Description=MySQL connection to 'asteriskcdrdb' database
Driver=MySQL ODBC 8.0 Unicode Driver
Server=localhost
Database=asteriskcdrdb
Port=3306
Socket=/run/mysqld/mysqld.sock
Option=3
Charset=utf8

[asterisk]
Driver=MySQL ODBC 8.0 Unicode Driver
Server=localhost
Database=asterisk
Port=3306
Socket=/run/mysqld/mysqld.sock
Option=3
Charset=utf8
EOF

# Ajustar Socket se for path legado
if [ -e "/var/run/mysqld/mysqld.sock" ]; then
  sed -i 's#Socket=/run/mysqld/mysqld.sock#Socket=/var/run/mysqld/mysqld.sock#g' /etc/odbc.ini
fi

# ===== Patches Issabel =====
if [ -d "$SOURCE_DIR_SCRIPT/issabel/patch" ]; then
  log "Aplicando patches do Issabel..."
  /usr/bin/cp -rf "$SOURCE_DIR_SCRIPT/issabel/patch/"*.patch /usr/src/issabelPBX || true
  cd /usr/src/issabelPBX
  for i in *.patch; do
    [ -f "$i" ] || continue
    echo "Apply patch $i"
    git apply --reject --whitespace=nowarn "$i" || true
  done
fi

# ===== Configurações do Asterisk =====
log "Ajustando configs do Asterisk..."
# manager.conf
if grep -q '^displayconnects' /etc/asterisk/manager.conf 2>/dev/null; then
  sed -i '/^displayconnects/d' /etc/asterisk/manager.conf
fi
grep -q 'manager_general_additional.conf' /etc/asterisk/manager.conf 2>/dev/null || \
  sed -i '/^\[general\]/a #include manager_general_additional.conf' /etc/asterisk/manager.conf

sed -i 's#/usr/share#/var/lib#g' /etc/asterisk/asterisk.conf || true

cat > /etc/asterisk/manager_general_additional.conf <<'EOF'
displayconnects=yes
timestampevents=yes
webenabled=no
EOF
chown asterisk:asterisk /etc/asterisk/manager_general_additional.conf
chown -R asterisk:asterisk /var/lib/asterisk/agi-bin || true

# ===== PEAR DB =====
log "Instalando PEAR::DB..."
yes '' | pear install DB || true

# ===== Compilar IssabelPBX =====
log "Compilando IssabelPBX..."
cd /usr/src/issabelPBX
build/compile_gettext.sh

# ===== Instalar IssabelPBX =====
log "Instalando IssabelPBX..."
framework/install_amp --dbuser=root --installdb --scripted --language="$LANGUAGE" --adminpass="$ISSABEL_ADMIN_PASSWORD"

# ===== Logrotate do Asterisk =====
if [ -f "$SOURCE_DIR_SCRIPT/logrotate/asterisk_logrotate.conf" ]; then
  /usr/bin/cp -f "$SOURCE_DIR_SCRIPT/logrotate/asterisk_logrotate.conf" /etc/logrotate.d/asterisk.conf
fi

# ===== Habilitar módulos Apache e reiniciar serviços =====
systemctl enable --now asterisk
systemctl restart asterisk
systemctl restart apache2
systemctl enable apache2 mariadb

# ===== Perl libs via CPAN (não interativo) =====
log "Instalando módulos Perl (LWP::Protocol::https, Digest::MD5)..."
PERL_MM_USE_DEFAULT=1 perl -MCPAN -e "install LWP::Protocol::https; install Digest::MD5" || true

log "Instalação concluída! Acesse: https://<IP_DO_SERVIDOR>/admin"
