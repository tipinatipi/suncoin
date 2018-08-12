#!/bin/bash

TMP_FOLDER=$(mktemp -d)
CONFIG_FILE='suncoin.conf'
CONFIGFOLDER='/root/.suncoincore'
COIN_DAEMON_FILE='suncoind'
COIN_CLI_FILE='suncoin-cli'
COIN_TX_FILE='suncoin-tx'
COIN_DAEMON='/usr/local/bin/suncoind'
COIN_CLI='/usr/local/bin/suncoin-cli'
COIN_TAG='sun'
COIN_REPO='https://github.com/suncoin-network/suncoin-core/releases/download/v1.0/suncoin-1.0-linux64.tar.gz'
SENTINEL_REPO='https://github.com/suncoin-network/sentinel.git'
COIN_NAME='SunCoin'
COIN_PORT=10332
#COIN_BS='http://bootstrap.zip'


NODEIP=$(curl -s4 icanhazip.com)


RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'


function install_sentinel() {
  echo -e "${GREEN}Install sentinel.${NC}"
  apt-get -y install python-virtualenv virtualenv
  cd
  git clone $SENTINEL_REPO sentinel
  cd sentinel
  virtualenv ./venv
  ./venv/bin/pip install -r requirements.txt
  CRONTAB_LINE="* * * * * cd /root/sentinel && ./venv/bin/python bin/sentinel.py >> $CONFIGFOLDER/sentinel.log 2>&1"
  (crontab -l; echo "$CRONTAB_LINE") | crontab -
  cd -
}


function download_node() {
  echo -e "${GREEN}Downloading $COIN_NAME binaries...${NC}"
  cd $TMP_FOLDER
  wget -q $COIN_REPO
  compile_error
  COIN_ZIP=$(echo $COIN_REPO | awk -F'/' '{print $NF}')
  tar xvf $COIN_ZIP --strip 1
  compile_error
  cd bin
  cp $COIN_DAEMON_FILE $COIN_CLI_FILE $COIN_TX_FILE /usr/local/bin
  compile_error
  strip $COIN_DAEMON $COIN_CLI
  cd -
  rm -rf $TMP_FOLDER
  chmod +x $COIN_DAEMON
  chmod +x $COIN_CLI
  clear
}

function configure_systemd() {
  cat << EOF > /etc/systemd/system/$COIN_NAME.service
[Unit]
Description=$COIN_NAME service
After=network.target

[Service]
User=root
Group=root

Type=forking
#PIDFile=$CONFIGFOLDER/$COIN_NAME.pid

ExecStart=$COIN_DAEMON -daemon -conf=$CONFIGFOLDER/$CONFIG_FILE -datadir=$CONFIGFOLDER
ExecStop=-$COIN_CLI -conf=$CONFIGFOLDER/$CONFIG_FILE -datadir=$CONFIGFOLDER stop

Restart=always
PrivateTmp=true
TimeoutStopSec=60s
TimeoutStartSec=10s
StartLimitInterval=120s
StartLimitBurst=5

[Install]
WantedBy=multi-user.target
EOF

  systemctl daemon-reload
  sleep 3
  systemctl start $COIN_NAME.service
  systemctl enable $COIN_NAME.service

  if [[ -z "$(ps axo cmd:100 | egrep $COIN_DAEMON)" ]]; then
    echo -e "${RED}$COIN_NAME is not running${NC}, please investigate. You should start by running the following commands as root:"
    echo -e "${GREEN}systemctl start $COIN_NAME.service"
    echo -e "systemctl status $COIN_NAME.service"
    echo -e "less /var/log/syslog${NC}"
    exit 1
  fi
}


function create_config() {
  echo -e "${GREEN}Creating configuration files in $CONFIGFOLDER.${NC}"
  mkdir $CONFIGFOLDER
  RPCUSER=$(tr -cd '[:alnum:]' < /dev/urandom | fold -w10 | head -n1)
  RPCPASSWORD=$(tr -cd '[:alnum:]' < /dev/urandom | fold -w22 | head -n1)
  cat << EOF > $CONFIGFOLDER/$CONFIG_FILE
rpcuser=$RPCUSER
rpcpassword=$RPCPASSWORD
rpcallowip=127.0.0.1
rpcport=4331
listen=1
server=1
daemon=1
masternode=1
port=$COIN_PORT
addnode=54.38.53.27
addnode=151.80.177.104
addnode=208.167.249.240
addnode=185.10.57.170
addnode=208.72.56.209
addnode=45.32.179.37
addnode=121.251.136.186
addnode=149.28.45.79
EOF
}

function create_key() {
  echo -e "Enter your ${RED}$COIN_NAME Masternode Private Key${NC}:"
  read -e COINKEY
  if [[ -z "$COINKEY" ]]; then
  $COIN_DAEMON -daemon
  sleep 30
  if [ -z "$(ps axo cmd:100 | grep $COIN_DAEMON)" ]; then
   echo -e "${RED}$COIN_NAME server couldn not start. Check /var/log/syslog for errors.{$NC}"
   exit 1
  fi
  COINKEY=$($COIN_CLI masternode genkey)
  if [ "$?" -gt "0" ];
    then
    echo -e "${RED}Wallet not fully loaded. Let us wait and try again to generate the Private Key${NC}"
    sleep 30
    COINKEY=$($COIN_CLI masternode genkey)
  fi
  $COIN_CLI stop
fi
clear
}

function update_config() {
  sed -i 's/daemon=1/daemon=0/' $CONFIGFOLDER/$CONFIG_FILE
  cat << EOF >> $CONFIGFOLDER/$CONFIG_FILE
logintimestamps=1
maxconnections=256
#bind=$NODEIP
masternode=1
externalip=$NODEIP
masternodeprivkey=$COINKEY
EOF
}


function enable_firewall() {
  echo -e "Installing and setting up firewall to allow ingress on port ${GREEN}$COIN_PORT${NC}"
  ufw allow $COIN_PORT/tcp comment "$COIN_NAME MN port" >/dev/null
  ufw allow ssh comment "SSH"
  ufw limit ssh/tcp
  ufw default allow outgoing
  echo "y" | ufw enable
  apt-get -y install fail2ban
  systemctl enable fail2ban
  systemctl start fail2ban
}



function get_ip() {
  declare -a NODE_IPS
  for ips in $(netstat -i | awk '!/Kernel|Iface|lo/ {print $1," "}')
  do
    NODE_IPS+=($(curl --interface $ips --connect-timeout 2 -s4 icanhazip.com))
  done

  if [ ${#NODE_IPS[@]} -gt 1 ]
    then
      echo -e "${GREEN}More than one IP. Please type 0 to use the first IP, 1 for the second and so on...${NC}"
      INDEX=0
      for ip in "${NODE_IPS[@]}"
      do
        echo ${INDEX} $ip
        let INDEX=${INDEX}+1
      done
      read -e choose_ip
      NODEIP=${NODE_IPS[$choose_ip]}
  else
    NODEIP=${NODE_IPS[0]}
  fi
}


function compile_error() {
if [ "$?" -gt "0" ];
 then
  echo -e "${RED}Failed to compile $COIN_NAME. Please investigate.${NC}"
  exit 1
fi
}


function checks() {
if [[ $(lsb_release -d) != *16.04* ]]; then
  echo -e "${RED}You are not running Ubuntu 16.04. Installation is cancelled.${NC}"
  exit 1
fi

if [[ $EUID -ne 0 ]]; then
   echo -e "${RED}$0 must be run as root.${NC}"
   exit 1
fi

if [ -n "$(pidof $COIN_DAEMON)" ] || [ -e "$COIN_DAEMOM" ] ; then
  echo -e "${RED}$COIN_NAME is already installed.${NC}"
  exit 1
fi
}

function prepare_system() {
echo -e "Preparing the system to install ${GREEN}$COIN_NAME${NC} master node."
echo -e "This might take 15-20 minutes and the screen will not move, so please be patient."
apt-get update
DEBIAN_FRONTEND=noninteractive apt-get update
DEBIAN_FRONTEND=noninteractive apt-get -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" -y -qq upgrade
apt-get upgrade
echo -e "${GREEN}Installing required dependencies, it may take some time to finish.${NC}"
apt-get update
apt-get install -y -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" build-essential libtool autotools-dev automake pkg-config libssl-dev libevent-dev bsdmainutils autoconf libboost-system-dev libboost-filesystem-dev libboost-chrono-dev libboost-program-options-dev libboost-test-dev libboost-thread-dev libboost-all-dev software-properties-common
echo -e "${GREEN}Adding bitcoin PPA repository"
apt-add-repository -y ppa:bitcoin/bitcoin
echo -e "${GREEN}Installing required packages.${NC}"
apt-get update
apt-get install -y -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" libdb4.8-dev libdb4.8++-dev libzmq3-dev git

if [ "$?" -gt "0" ];
  then
    echo -e "${RED}Not all required packages were installed properly. Try to install them manually by running the following commands:${NC}\n"
    echo "apt-get update"
    echo "apt-get install build-essential libtool autotools-dev automake pkg-config libssl-dev libevent-dev bsdmainutils autoconf"
    echo "apt-get install libboost-system-dev libboost-filesystem-dev libboost-chrono-dev libboost-program-options-dev libboost-test-dev libboost-thread-dev"
    echo "apt-get install libboost-all-dev"
    echo "apt-get install software-properties-common"
    echo "apt-add-repository -y ppa:bitcoin/bitcoin"
    echo "apt-get update"
    echo "apt-get install libdb4.8-dev libdb4.8++-dev libzmq3-dev"
    echo "apt-get install git"
 exit 1
fi

clear
}


function important_information() {
 echo
 echo -e "================================================================================================================================"
 echo -e "$COIN_NAME Masternode is up and running listening on port ${RED}$COIN_PORT${NC}."
 echo -e "Configuration file is: ${RED}$CONFIGFOLDER/$CONFIG_FILE${NC}"
 echo -e "Start: ${RED}systemctl start $COIN_NAME.service${NC}"
 echo -e "Stop: ${RED}systemctl stop $COIN_NAME.service${NC}"
 echo -e "VPS_IP:PORT ${RED}$NODEIP:$COIN_PORT${NC}"
 echo -e "MASTERNODE PRIVATEKEY is: ${RED}$COINKEY${NC}"
 if [[ -n $SENTINEL_REPO  ]]; then
  echo -e "${RED}Sentinel${NC} is installed in ${RED}/sentinel${NC}"
  echo -e "Sentinel logs is: ${RED}$CONFIGFOLDER/sentinel.log${NC}"
 fi
 echo -e "Please check ${RED}$COIN_NAME${NC} is running with the following command: ${RED}systemctl status $COIN_NAME.service${NC}"
 echo -e "================================================================================================================================"
}

function import_bootstrap() {
  wget -q $COIN_BS
  compile_error
  COIN_ZIP=$(echo $COIN_BS | awk -F'/' '{print $NF}')
  unzip $COIN_ZIP
  compile_error
  cp -r ~/bootstrap/blocks ~/.acedcore/blocks
  cp -r ~/bootstrap/chainstate ~/.acedcore/chainstate
  cp -r ~/bootstrap/peers.dat ~/.acedcore/peers.dat
  rm -r ~/bootstrap/
  rm $COIN_ZIP
}

function setup_node() {
  get_ip
  create_config
  #import_bootstrap
  create_key
  update_config
  enable_firewall
  install_sentinel
  important_information
  configure_systemd
}


##### Main #####
clear

checks
prepare_system
download_node
setup_node
