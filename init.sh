#!/bin/bash

#OS-UPDATE
apt update && apt upgrade -y

#DIRECTORY
mkdir /media/share
mkdir /home/seki/docker
mkdir /home/seki/docker/{homer,prometheus,portainer-data,vpn-data,speedtest}

#INSTALL-APPS
apt install ufw -y && apt install nano -y && apt install btop -y

#DOCKER
sudo apt install docker -y && sudo apt install docker-compose -y
groupadd --system dockergroup && useradd --system --no-create-home --group dockergroup,seki -s /bin/false docker
chown -R seki:docker /home/seki
usermod -aG docker,adm seki

#SAMBA
apt install samba 
groupadd --system smbgroup && useradd --system --no-create-home --group smbgroup -s /bin/false smbuser
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

service smbd start && systemctl start smbd && systemctl restart smbd nmbd

#PLEX
apt install apt-transport-https curl wget -y
wget -O- https://downloads.plex.tv/plex-keys/PlexSign.key | gpg --dearmor | sudo tee /usr/share/keyrings/plex.gpg
echo deb [signed-by=/usr/share/keyrings/plex.gpg] https://downloads.plex.tv/repo/deb public main | sudo tee /etc/apt/sources.list.d/plexmediaserver.list
apt update
echo N | apt install plexmediaserver -y
systemctl start plexmediaserver && systemctl enable plexmediaserver && systemctl restart plexmediaserver
groupadd --system plexgroup && useradd --system --no-create-home --group plexgroup -s /bin/false plex
chown -R plex: /media/share

cat <<EOF > /etc/ufw/applications.d/plexmediaserver
[plexmediaserver]
title=Plex Media Server (Standard)
description=The Plex Media Server
ports=32400/tcp|3005/tcp|5353/udp|8324/tcp|32410:32414/udp

[plexmediaserver-dlna]
title=Plex Media Server (DLNA)
description=The Plex Media Server (additional DLNA capability only)
ports=1900/udp|32469/tcp

[plexmediaserver-all]
title=Plex Media Server (Standard + DLNA)
description=The Plex Media Server (with additional DLNA capability)
ports=32400/tcp|3005/tcp|5353/udp|8324/tcp|32410:32414/udp|1900/udp|32469/tcp
EOF
