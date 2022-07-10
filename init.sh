#!/bin/bash

source .var

#LAPTOP-LID-OFF
cat <<EOF >> /etc/systemd/logind.conf
HandleSuspendKey=ignore
HandleLidSwitch=ignore
HandleLidSwitchDocked=ignore
EOF
systemctl restart systemd-logind

#TIMEZONE
timedatectl set-timezone "$TIMEZONE"

#SSH-LOCK
echo "$KEY" >> /home/$USER/.ssh/authorized_keys
cat <<EOF >> /etc/ssh/sshd_config
MaxAuthTries 3
PermitRootLogin no
PasswordAuthentication no
PermitEmptyPasswords no
UsePAM yes
PubkeyAuthentication yes
EOF

#UPDATES
apt update
apt upgrade -y

#INSTALL-APPS
apt install cron -y
apt install nano -y
apt install btop -y
apt install git -y

#DIRECTORY
mkdir /media/share
mkdir /media/share/{backup,Downloads}
mkdir /home/"$USER"/docker
mkdir /home/"$USER"/backup
mkdir /home/"$USER"/backup/{daily,weekly,monthly}
mkdir /home/"$USER"/backup-task
mkdir /home/"$USER"/docker/{nginx,homer,prometheus,portainer-data,speedtest,filebrowser,pihole,qbit,focalboard,nextcloud}
mkdir /home/"$USER"/docker/nextcloud/{config,data}
mkdir /home/"$USER"/docker/nginx/{mysql,data,letsencrypt}
mkdir /home/"$USER"/docker/pihole/{etc-pihole,etc-dnsmasq.d}


#HDD-MOUNT
cat <<EOF >> /etc/fstab
/dev/sdc1 /media/share auto nosuid,nodev,nofail 0 0
/dev/sdb2 /media/share auto nosuid,nodev,nofail 0 0
/dev/sdd1 /media/share auto nosuid,nodev,nofail 0 0
EOF

#CROWDSEC
curl -s https://packagecloud.io/install/repositories/crowdsec/crowdsec/script.deb.sh | sudo bash
apt install crowdsec -y
apt install crowdsec-firewall-bouncer-iptables -y
systemctl enable crowdsec
systemctl start crowdsec
cscli collections install crowdsecurity/whitelist-good-actors
sudo cscli parsers install crowdsecurity/iptables-logs
sudo cscli hub update
sudo cscli parsers upgrade crowdsecurity/sshd-logs 

systemctl reload crowdsec

#UFW
apt install ufw -y
ufw default reject incoming
ufw default allow outgoing
ufw allow 80/tcp   #HTTP
ufw allow 443/tcp  #HTTPS
ufw allow 881/tcp  #Pihole
ufw allow 2222/tcp #Filebrowser
ufw allow 3030/tcp #Grafana
ufw allow 4040/tcp #SpeedTest
ufw allow 5151/tcp #Homr
ufw allow 8585/tcp #Nginx
ufw limit 9000     #Prometheus
ufw allow 9090/tcp #Porteiner
ufw allow 9091/tcp #Authelia
ufw limit 1111     #Qbittorrent
ufw limit 6881/tcp #Qbittorrent
ufw limit 6881/udp #Qbittorrent
ufw allow 5253     #Focalboard
ufw allow 5254     #NextCloud


#SAMBA
apt install samba -y
groupadd --system smbgroup
useradd --system --no-create-home --group smbgroup -s /bin/false smbuser
chown -R smbuser:smbgroup /media/share

cat <<EOF > /etc/samba/smb.conf
[global]
server string = File Server
workgroup = WORKGROUP
security = user
map to guest = Bad User
name resolve order = bcast host
include = /etc/samba/shares.conf
EOF

cat <<EOF > /etc/samba/shares.conf
[Public Files]
path = /media/share
force user = smbuser
force group = smbgroup
create mask = 0664
force create mode = 0664
directory mask = 0775
force directory mode = 0775
public = yes
writable = yes
EOF

systemctl start smbd
ufw allow from "$SUBNET" to any app Samba
systemctl restart smbd nmbd

#PLEX
apt install apt-transport-https curl wget -y
wget -O- https://downloads.plex.tv/plex-keys/PlexSign.key | gpg --dearmor | sudo tee /usr/share/keyrings/plex.gpg
echo deb [signed-by=/usr/share/keyrings/plex.gpg] https://downloads.plex.tv/repo/deb public main | sudo tee /etc/apt/sources.list.d/plexmediaserver.list
apt update
echo N | apt install plexmediaserver -y
groupadd --system plexgroup
useradd --system --no-create-home --group plexgroup -s /bin/false plexserver
chown -R plexserver: /media/share

systemctl enable plexmediaserver
systemctl start plexmediaserver

cat <<EOF > /etc/ufw/applications.d/plexmediaserver
[plexmediaserver-all]
title=Plex Media Server (Standard + DLNA)
description=The Plex Media Server (with additional DLNA capability)
ports=32400/tcp|3005/tcp|5353/udp|8324/tcp|32410:32414/udp|1900/udp|32469/tcp
EOF

ufw app update plexmediaserver
ufw allow plexmediaserver-all
systemctl restart plexmediaserver

#DOCKER
apt install docker.io -y
apt install docker-compose -y
groupadd --system dockergroup
useradd --system --no-create-home --group dockergroup,"$USER" -s /bin/false docker
chown -R "$USER":docker /home/"$USER"
usermod -aG docker,adm "$USER"

docker network create proxy
cp ./docker-compose.yml /home/"$USER"/docker/docker-compose.yml
cp ./homer.yml /home/"$USER"/docker/homer/config.yml

cat <<EOF > /home/"$USER"/docker/.env
USER="${USER}"
SITE="${SITE}"
TIMEZONE="${TIMEZONE}"
PUID="${PUID}"
PGID="${PGID}"
DNSAPI="${DNSAPI}"
ROOT_PASSWORD="${ROOT_PASSWORD}"
MYSQL_DATABASE="${MYSQL_DATABASE}"
MYSQL_USER="${MYSQL_USER}"
MYSQL_PASSWORD="${MYSQL_PASSWORD}"
EOF

cat <<EOF > /home/$USER/docker/prometheus/prometheus.yml
global:
  scrape_interval:     15s # By default, scrape targets every 15 seconds.

  # Attach these labels to any time series or alerts when communicating with
  # external systems (federation, remote storage, Alertmanager).
  # external_labels:
  #  monitor: 'codelab-monitor'

# A scrape configuration containing exactly one endpoint to scrape:
# Here it's Prometheus itself.
scrape_configs:
  # The job name is added as a label `job=<job_name>` to any timeseries scraped from this config.
  - job_name: 'prometheus'
    # Override the global default and scrape targets from this job every 5 seconds.
    scrape_interval: 5s
    static_configs:
      - targets: ['localhost:9090']

  # Example job for node_exporter
  - job_name: 'node_exporter'
    static_configs:
      - targets: ['node_exporter:9100']

  # Example job for cadvisor
  - job_name: 'cadvisor'
    static_configs:
      - targets: ['cadvisor:8080']
EOF

setfacl -m "u:root:rw" /home/"$USER"/docker/.env
docker-compose -f /home/"$USER"/docker/docker-compose.yml --env-file /home/"$USER"/docker/.env up -d

#BACKUP
cat <<EOF >> /home/"$USER"/backup-task/backup-daily.sh
#!/bin/bash

docker-compose -f /home/"$USER"/docker/docker-compose.yml pause
tar --exclude=/home/"$USER"/docker/qbit/config/qBittorrent/ipc-socket -zcf /home/"$USER"/backup/daily/backup-\$(date +%Y%m%d).tar.gz -C /home/"$USER"/docker/*
find /home/"$USER"/backup/daily/* -mtime +7 -delete
docker-compose -f /home/"$USER"/docker/docker-compose.yml unpause
EOF
chmod +x /home/"$USER"/backup-task/backup-daily.sh

cat <<EOF >> /home/"$USER"/backup-task/backup-weekly.sh
#!/bin/bash

docker-compose -f /home/"$USER"/docker/docker-compose.yml pause
tar --exclude=/home/"$USER"/docker/qbit/config/qBittorrent/ipc-socket -zcf /home/"$USER"/backup/weekly/backup-\$(date +%Y%m%d).tar.gz -C /home/"$USER"/docker/*
find /home/"$USER"/backup/weekly/* -mtime +31 -delete
docker-compose -f /home/"$USER"/docker/docker-compose.yml unpause
EOF
chmod +x /home/"$USER"/backup-task/backup-weekly.sh

cat <<EOF >> /home/"$USER"/backup-task/backup-monthly.sh
#!/bin/bash

docker-compose -f /home/"$USER"/docker/docker-compose.yml pause
tar --exclude=/home/"$USER"/docker/qbit/config/qBittorrent/ipc-socket -zcf /home/"$USER"/backup/monthly/backup-\$(date +%Y%m%d).tar.gz -C /home/"$USER"/docker/*
find /home/"$USER"/backup/monthly/* -mtime +365 -delete
docker-compose -f /home/"$USER"/docker/docker-compose.yml unpause
EOF
chmod +x /home/"$USER"/backup-task/backup-monthly.sh

#CRONTAB
cat <<EOF >> /etc/cron.d/crontask
0 5 * * *  root    apt update && apt upgrade -y
20 5 * * * root    cscli hub update && cscli collections upgrade crowdsecurity/sshd && systemctl reload crowdsec
25 5 * * * root    docker system prune -a -f
30 5 * * * root    /home/"$USER"/backup-task/backup-daily.sh
40 5 * * 1 root    /home/"$USER"/backup-task/backup-weekly.sh
50 5 1 * * root    /home/"$USER"/backup-task/backup-monthly.sh
EOF
crontab -u "$USER" /etc/cron.d/crontask

#ALIAS
cat <<EOF >> ~/.bashrc
alias clean-downloads='sudo rm -rf /media/share/Downloads && sudo mkdir /media/share/Downloads && sudo sudo chown -R smbuser:smbgroup /media/share/Downloads'
EOF
source ~/.bashrc
#LOG
cat <<EOF > ./init-log

###############################################################
|
|   SERVER INFO:
|
|     OS VERSION:      $OSVER
|
|     USER INFO:
|
|        - Username:   $USER
|
|     NETWORK:
|
|        - Public IP:  $PUBIP
|        - Subnet:     $SUBNET
|        - NetAdapter: $NETADAPT
|
|     WEB:
|
|        - Pihole:     $IP:881
|        - Qbittorrent:$IP:1111
|        - Filemenager:$IP:2222
|        - Grafana:    $IP:3030
|        - SpeedTest:  $IP:4040
|        - Focalboard: $IP:5253
|        - NextCloud:  $IP:5254
|        - Nginx:      $IP:8585
|        - Authelia   :$IP:9091
|        - Portainer:  $IP:9090
|        - Prometheus: $IP:9000
|
###############################################################
|
|     CONNECT TO:
|
|        DASHBOARD ==> $IP:5050
|              SSH ==> ssh $USER@$IP
|
###############################################################
EOF

cat ./init-log
ufw --force enable
systemctl restart sshd