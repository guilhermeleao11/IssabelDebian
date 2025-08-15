#!/bin/bash

################################################################################
# Nome do Script : install_issabel_asterisk20.sh
# Desenvolvedor  : Guilherme Leão - Telium Network (revisado)
# Data           : 15/08/2025
# Versão         : 2.0
# Objetivo       : Instalar Issabel no Debian 12 com Asterisk 20 LTS (pjsip + chansip + CDR)
################################################################################

# ===== VARIÁVEIS =====
ASTERISK_VERSION="20.9.3"
ASTERISK_URL="https://downloads.asterisk.org/pub/telephony/asterisk/releases"
SENHA_MANAGER="${1:-senha123}"  # Pode passar a senha na chamada do script
LOG_FILE="/var/log/install_issabel_asterisk.log"

# ===== FUNÇÃO DE LOG =====
log() {
    echo -e "\e[32m[INFO]\e[0m $1"
    echo "[INFO] $1" >> "$LOG_FILE"
}

# ===== CHECK DO SISTEMA =====
check_sistema() {
    log "Verificando sistema..."
    if [[ "$(id -u)" -ne 0 ]]; then
        echo "Este script precisa ser executado como root!"
        exit 1
    fi
    apt update -y && apt upgrade -y
}

# ===== INSTALAR DEPENDÊNCIAS =====
instalar_dependencias() {
    log "Instalando dependências..."
    apt install -y build-essential git wget curl unzip tar \
        libxml2-dev libncurses5-dev uuid-dev libjansson-dev \
        libssl-dev libsqlite3-dev libedit-dev pkg-config \
        unixodbc unixodbc-dev libmyodbc libpq-dev \
        mariadb-server mariadb-client \
        php php-cli php-mysql php-mbstring php-pear php-xml \
        libapache2-mod-php apache2 sox mpg123
}

# ===== INSTALAR PHP 7.4 =====
instalar_php74() {
    log "Instalando PHP 7.4..."
    apt install -y ca-certificates apt-transport-https software-properties-common
    add-apt-repository ppa:ondrej/php -y
    apt update
    apt install -y php7.4 php7.4-cli php7.4-mysql php7.4-mbstring php7.4-xml libapache2-mod-php7.4
}

# ===== CRIAR USUÁRIO ASTERISK =====
criar_usuario_asterisk() {
    log "Criando usuário e diretórios do Asterisk..."
    if ! id -u asterisk >/dev/null 2>&1; then
        useradd -r -s /usr/sbin/nologin -d /var/lib/asterisk asterisk
    fi
    mkdir -p /var/{lib,log,spool,run}/asterisk
    chown -R asterisk:asterisk /var/{lib,log,spool,run}/asterisk
}

# ===== CONFIGURAR MENUSELECT =====
configurar_menuselect() {
    log "Configurando módulos do Asterisk..."
    make menuselect.makeopts
    menuselect/menuselect \
        --enable cdr_csv \
        --enable cdr_adaptive_odbc \
        --enable chan_pjsip \
        --enable chan_sip \
        --enable app_macro \
        --enable res_http_websocket \
        --enable res_pjproject \
        --enable res_pjsip \
        --enable res_pjsip_endpoint_identifier_ip \
        --enable res_pjsip_exten_state \
        --enable res_pjsip_logger \
        --enable res_pjsip_registrar \
        --enable res_pjsip_sdp_rtp \
        --enable res_rtp_asterisk \
        --enable res_srtp \
        --enable res_stasis \
        menuselect.makeopts
}

# ===== INSTALAR ASTERISK =====
instalar_asterisk() {
    log "Baixando e compilando Asterisk $ASTERISK_VERSION..."
    cd /usr/src
    wget -q "${ASTERISK_URL}/asterisk-${ASTERISK_VERSION}.tar.gz"
    tar xzf "asterisk-${ASTERISK_VERSION}.tar.gz"
    cd "asterisk-${ASTERISK_VERSION}"
    contrib/scripts/install_prereq install
    ./configure
    configurar_menuselect
    make -j$(nproc)
    make install
    make samples
    make config
    ldconfig
    systemctl enable asterisk
}

# ===== CONFIGURAR ARQUIVOS OBRIGATÓRIOS =====
configurar_arquivos() {
    log "Garantindo arquivos de configuração..."
    # manager.conf
    if [ ! -f /etc/asterisk/manager.conf ]; then
        cat > /etc/asterisk/manager.conf <<EOF
[general]
enabled = yes
webenabled = no
displayconnects = yes
timestampevents = yes

[admin]
secret = ${SENHA_MANAGER}
read = all
write = all
EOF
        chown asterisk:asterisk /etc/asterisk/manager.conf
    fi

    # cdr.conf
    if [ ! -f /etc/asterisk/cdr.conf ]; then
        echo "[general]" > /etc/asterisk/cdr.conf
        echo "enable=yes" >> /etc/asterisk/cdr.conf
        chown asterisk:asterisk /etc/asterisk/cdr.conf
    fi
}

# ===== INSTALAR ISSABEL =====
instalar_issabel() {
    log "Instalando Issabel..."
    cd /usr/src
    git clone https://github.com/rojasrjosee/issabel-debian
    cd issabel-debian
    bash install.sh
}

# ===== FINALIZAR =====
finalizar() {
    log "Instalação concluída!"
    echo "Acesse o Issabel via http://IP_DO_SERVIDOR"
    echo "Usuário AMI: admin / Senha: ${SENHA_MANAGER}"
}

# ===== EXECUÇÃO =====
check_sistema
instalar_dependencias
instalar_php74
criar_usuario_asterisk
instalar_asterisk
configurar_arquivos
instalar_issabel
finalizar