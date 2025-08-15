
#!/bin/bash
################################################################################
# Nome do Script: InstallDebian.sh
# Desenvolvedor : Guilherme Leão - Telium Network
# Data          : 14/08/2025
# Versão        : 1.0
# Motivo/Objetivo: Script para instalar o framework Issabel no Debian 12
################################################################################

echo "Iniciando o script de instalação do Issabel no Debian 12"

##############################
# Variáveis do Asterisk
##############################
ASTERISK_SRC_FILE="${ASTERISK_SRC_FILE:-asterisk-20-current.tar.gz}"
ASTERISK_URL="${ASTERISK_URL:-https://downloads.asterisk.org/pub/telephony/asterisk}"
ASTERISK_URL_CERTIFIED="${ASTERISK_URL_CERTIFIED:-https://downloads.asterisk.org/pub/telephony/asterisk/certified}"

##############################
# Variáveis do Issabel
##############################
SOURCE_DIR_SCRIPT="/usr/src/issabel-install"
LANGUAGE="${LANGUAGE:-en_EN}"
ISSABEL_ADMIN_PASSWORD="${ISSABEL_ADMIN_PASSWORD:-Mudar123@}"

##############################
# Adiciona sbin ao PATH
##############################
grep -q '/usr/sbin' /etc/bash.bashrc || echo "export PATH=\$PATH:/usr/local/sbin:/usr/sbin" >> /etc/bash.bashrc
echo "$PATH" | grep -q 'sbin' || { echo "Error: /usr/sbin not in PATH"; exit 1; }

##############################
# Habilita repositórios contrib e non-free
##############################
grep -q 'main.*contrib.*non-free' /etc/apt/sources.list || \
    sed -i -E 's/^(deb.+)main(.+)/\1main contrib non-free\2/' /etc/apt/sources.list

##############################
# Atualiza sistema e instala pacotes básicos
##############################
apt update && apt upgrade -y
apt install -y apt-transport-https lsb-release ca-certificates wget curl aptitude git apache2 mariadb-server mariadb-client \
    unixodbc odbcinst unixodbc-dev libmariadb-dev cockpit net-tools dialog locales-all libwww-perl mpg123 sox \
    fail2ban cracklib-runtime dnsutils certbot python3-certbot-apache iptables libapache2-mod-php7.4 \
    php7.4-cli php7.4-common php7.4-curl php7.4-json php7.4-mbstring php7.4-mysql php7.4-opcache php7.4-readline \
    php7.4-sqlite3 php7.4-xml php-pear

##############################
# Instala PHP 7.4
##############################
wget -O /etc/apt/trusted.gpg.d/php.gpg https://packages.sury.org/php/apt.gpg
echo "deb https://packages.sury.org/php/ $(lsb_release -sc) main" | sudo tee /etc/apt/sources.list.d/php.list
apt update
apt-mark hold php8*
apt install -y libapache2-mod-php7.4 php7.4-cli php7.4-common php7.4-curl php7.4-json php7.4-mbstring \
    php7.4-mysql php7.4-opcache php7.4-readline php7.4-sqlite3 php7.4-xml php-pear

##############################
# Ajusta diretórios do Asterisk
##############################
if [ -d /usr/lib/x86_64-linux-gnu/asterisk/modules ]; then
    mkdir -p /usr/lib/asterisk
    ln -s /usr/lib/x86_64-linux-gnu/asterisk/modules /usr/lib/asterisk
fi

##############################
# Criação do usuário Asterisk
##############################
if ! id -u "asterisk" >/dev/null 2>&1; then
    useradd -r -s /usr/sbin/nologin -d /var/lib/asterisk asterisk
    mkdir -p /var/lib/asterisk
    chown asterisk:asterisk /var/lib/asterisk
fi

##############################
# Download do Asterisk
##############################
ASTERISK_SRC_DIR="$(basename $ASTERISK_SRC_FILE .tar.gz)"
ASTERISK_URL_DOWNLOAD=$ASTERISK_URL/$ASTERISK_SRC_FILE
if echo "$ASTERISK_SRC_FILE" | grep -Fq "certified"; then
    ASTERISK_URL_DOWNLOAD=$ASTERISK_URL_CERTIFIED/$ASTERISK_SRC_FILE
fi

cd /usr/src
[[ -f $ASTERISK_SRC_FILE ]] || { wget $ASTERISK_URL_DOWNLOAD; }
[[ -d /usr/src/${ASTERISK_SRC_DIR} ]] || mkdir -p /usr/src/${ASTERISK_SRC_DIR}
tar zxvf $ASTERISK_SRC_FILE -C /usr/src/${ASTERISK_SRC_DIR} --strip-components=1
cd ${ASTERISK_SRC_DIR}/

##############################
# Instala dependências do Asterisk
##############################
contrib/scripts/install_prereq install

##############################
# Configura e compila o Asterisk
##############################
./configure
make menuselect.makeopts menuselect/menuselect \
    --disable-category MENUSELECT_ADDONS \
    --disable app_flash \
    --disable app_skel \
    --disable-category MENUSELECT_CDR \
    --disable-category MENUSELECT_CEL \
    --disable cdr_pgsql \
    --disable cel_pgsql \
    --disable-category MENUSELECT_CHANNELS \
    --enable chan_iax2 \
    --enable chan_pjsip \
    --enable chan_rtp \
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
    --disable res_odbc \
    --disable res_odbc_transaction \
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
    --enable res_stasis_mailbox \
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
    --disable res_config_ldap \
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
    --enable res_timing_kqueue \
    --disable res_timing_pthread \
    --disable res_adsi \
    --enable res_config_sqlite3 \
    --disable res_monitor \
    --disable res_digium_phone \
    --disable res_mwi_external \
    --disable res_stasis_mailbox \
    --enable cdr_adaptive_odbc \
    --enable cdr_custom \
    --enable cdr_manager \
    --enable cdr_csv \
    menuselect.makeopts

make
make install
##############################
# Ajusta serviço systemd
##############################
cat > /lib/systemd/system/asterisk.service <<EOF
[Unit]
Description=LSB: Asterisk PBX
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=asterisk
Group=asterisk
ExecStart=/usr/sbin/asterisk -U asterisk -G asterisk -mqf -C /etc/asterisk/asterisk.conf
ExecReload=/usr/sbin/asterisk -rx 'core reload'
Restart=on-failure
LimitCORE=infinity
LimitNOFILE=infinity
LimitNPROC=infinity
LimitMEMLOCK=infinity

[Install]
WantedBy=multi-user.target
EOF

##############################
# Download e instalação do Issabel
##############################
cd /usr/src
git clone https://github.com/asternic/issabelPBX.git
cd issabelPBX
build/compile_gettext.sh
framework/install_amp --dbuser=root --installdb --scripted --language=$LANGUAGE --adminpass=$ISSABEL_ADMIN_PASSWORD

##############################
# Ajustes Apache
##############################
if [ -f /var/www/html/index.html ]; then
    mv /var/www/html/index.html /var/www/html/index.html.bak
fi
cat > /var/www/html/index.html <<EOF
<html>
<head>
<meta http-equiv="refresh" content="0; url=/admin">
</head>
<body></body>
</html>
EOF
sed -i -e "s/www-data/asterisk/" /etc/apache2/envvars
a2enmod rewrite ssl
ln -sf /etc/apache2/sites-available/default-ssl.conf /etc/apache2/sites-enabled/

##############################
# Reinicia serviços
##############################
systemctl daemon-reload
systemctl enable asterisk
systemctl restart asterisk
systemctl restart apache2

echo "Instalação concluída com sucesso!"