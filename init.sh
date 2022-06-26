#!/bin/bash

source .var

#LAPTOP-LID-OFF
cat <<EOF >> /etc/systemd/logind.conf
HandleSuspendKey=ignore
HandleLidSwitch=ignore
HandleLidSwitchDocked=ignore
EOF
systemctl restart systemd-logind
timedatectl set-timezone "$TIMEZONE"

#UPDATES
apt update
apt upgrade -y

#INSTALL-APPS
apt install nano -y
apt install btop -y
apt install git -y

#DIRECTORY
mkdir /media/share
mkdir /home/"$USER"/docker
mkdir /home/"$USER"/docker/{homer,prometheus,portainer-data,vpn-data,speedtest,filebrowser,hugo}

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
systemctl reload crowdsec

#UFW
apt install ufw -y
ufw default reject incoming
ufw default allow outgoing
ufw allow 80/tcp   #HTTP
ufw allow 443/tcp  #HTTPS
ufw allow 9595/tcp #Homr
ufw allow 3030/tcp #Grafana
ufw limit 9000     #Prometheus
ufw limit 2020     #Qbittorrent
ufw limit 6881/tcp #Qbittorrent
ufw limit 6881/udp #Qbittorrent

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
USER=${USER}
SITE=${SITE}
TIMEZONE=${TIMEZONE}
PUID=${PUID}
PGID=${PGID}
DNSAPI=${DNSAPI}
ROOT_PASSWORD=${ROOT_PASSWORD}
MYSQL_DATABASE=${MYSQL_DATABASE}
MYSQL_USER=${MYSQL_USER}
MYSQL_PASSWORD=${MYSQL_PASSWORD}
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

#CRONTAB
cat <<EOF >> /etc/crontab
0 5 * * * root    apt update && apt upgrade -y
20 5 * * * root    cscli hub update && cscli collections upgrade crowdsecurity/sshd && systemctl reload crowdsec
30 5 * * * root    docker system prune -a -f
EOF

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
|        - Nginx:      $IP:8585
|        - Portainer:  $IP:9090
|        - Grafana:    $IP:3030
|        - SpeedTest:  $IP:4040
|        - Prometheus: $IP:9000
|        - Qbittorrent:$IP:2020
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