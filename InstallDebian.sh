#!/bin/bash
################################################################################
# Script de instalação Asterisk 20 LTS + Issabel no Debian 12
# Autor: Guilherme Leão
# Objetivo: Instalar Asterisk 20 LTS com suporte chan_sip + pjsip + CDR
#           e instalar Issabel, mantendo o Asterisk já instalado.
################################################################################

# --- Variáveis ---
AST_VER="20.7.0"  # Última LTS estável
AST_USER="asterisk"
AMI_USER="admin"
AMI_PASS="Mudar123@"    # Senha AMI
DB_PASS="Mudar123@"     # Senha root do MariaDB

# --- Funções ---
check_root() {
    if [ "$(id -u)" -ne 0 ]; then
        echo "Este script precisa ser executado como root."
        exit 1
    fi
}

install_deps() {
    echo "Instalando dependências..."
    apt update
    apt install -y curl wget build-essential git subversion \
        libxml2-dev libncurses5-dev uuid-dev libjansson-dev libssl-dev \
        libsqlite3-dev libedit-dev pkg-config automake libtool \
        mariadb-server mariadb-client unixodbc unixodbc-dev libmyodbc \
        odbcinst odbcinst1debian2 bison flex
}

install_php74() {
    echo "Instalando PHP 7.4 (repositório Sury)..."
    apt install -y lsb-release ca-certificates apt-transport-https software-properties-common gnupg2
    wget -qO - https://packages.sury.org/php/apt.gpg | apt-key add -
    echo "deb https://packages.sury.org/php $(lsb_release -sc) main" | tee /etc/apt/sources.list.d/php.list
    apt update
    apt install -y php7.4 php7.4-cli php7.4-mysql php7.4-gd php7.4-curl php7.4-xml php7.4-mbstring
}

create_asterisk_user() {
    echo "Criando usuário $AST_USER..."
    adduser --quiet --system --group --home /var/lib/asterisk $AST_USER
}

install_asterisk() {
    echo "Baixando e instalando Asterisk $AST_VER..."
    cd /usr/src
    wget https://downloads.asterisk.org/pub/telephony/asterisk/asterisk-${AST_VER}.tar.gz
    tar xvf asterisk-${AST_VER}.tar.gz
    cd asterisk-${AST_VER}
    contrib/scripts/get_mp3_source.sh
    ./configure
    make menuselect.makeopts
    menuselect/menuselect --enable chan_sip --enable res_pjsip --enable res_pjsip_pubsub \
                          --enable res_pjsip_exten_state --enable res_pjsip_registrar \
                          --enable format_mp3 menuselect.makeopts
    make
    make install
    make samples
    make config
    ldconfig
}

config_permissions() {
    echo "Configurando permissões do Asterisk..."
    chown -R $AST_USER:$AST_USER /var/{lib,log,spool}/asterisk /usr/lib/asterisk
    chown -R $AST_USER:$AST_USER /etc/asterisk
    chmod -R 750 /var/{lib,log,spool}/asterisk /usr/lib/asterisk
}

config_manager_conf() {
    echo "Configurando manager.conf..."
    MANAGER_CONF="/etc/asterisk/manager.conf"
    cat > "$MANAGER_CONF" <<EOF
[general]
enabled = yes
webenabled = yes
port = 5038
bindaddr = 0.0.0.0

[$AMI_USER]
secret = $AMI_PASS
read = all
write = all
EOF
    chown $AST_USER:$AST_USER "$MANAGER_CONF"
}

config_cdr() {
    echo "Configurando CDR..."
    cat > /etc/asterisk/cdr.conf <<EOF
[general]
enable=yes
unanswered = yes
endbeforehexten = no
initiatedseconds = no
EOF

    cat > /etc/asterisk/cdr_adaptive_odbc.conf <<EOF
[adaptive_connection]
connection=asteriskcdrdb
table=cdr
alias start => calldate
EOF

    cat > /etc/odbc.ini <<EOF
[MySQL-asteriskcdrdb]
Description=MySQL connection to CDR
Driver=MySQL ODBC 8.0 Unicode Driver
Server=localhost
Database=asteriskcdrdb
User=root
Password=$DB_PASS
Port=3306
Socket=/var/run/mysqld/mysqld.sock
EOF

    cat > /etc/odbcinst.ini <<EOF
[MySQL ODBC 8.0 Unicode Driver]
Driver=/usr/lib/x86_64-linux-gnu/odbc/libmyodbc8w.so
EOF
}

install_issabel() {
    echo "Instalando Issabel (adaptado)..."
    cd /usr/src
    git clone https://github.com/rojasrjosee/issabel-debian
    cd issabel-debian
    sed -i '/asterisk/d' install.sh  # Remove instalação automática do Asterisk
    sed -i '/yum/d' install.sh       # Remove comandos YUM (CentOS)
    sed -i '/dnf/d' install.sh
    bash install.sh
}

start_services() {
    echo "Ativando e iniciando serviços..."
    systemctl enable asterisk
    systemctl start asterisk
    systemctl enable mariadb
    systemctl start mariadb
}

# --- Execução ---
check_root
install_deps
install_php74
create_asterisk_user
install_asterisk
config_permissions
config_manager_conf
config_cdr
install_issabel
start_services

echo "Instalação concluída!"
echo "AMI User: $AMI_USER / Senha: $AMI_PASS"
echo "MariaDB root senha: $DB_PASS"
