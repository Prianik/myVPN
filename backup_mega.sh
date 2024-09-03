#! /bin/bash

_TOKEN=9042c1b445527532sdfsdfsdfsdfsdfsdfds
_DOMAIN=atm52.freemyip.com
NAMEARH=xray-atm


#логин-пароль от MEGA
_MEGA_USER=user
_MEGA_PASS=pass
#
day=$(date +%Y_%m_%d-%H%M)
CLOUD_BACKUPS_DIR="${_DOMAIN}"
LOCAL_BACKUPS_DIR="/tmp/${CLOUD_BACKUPS_DIR}"
fname=${day}-${NAMEARH}
BACKUP_COUNT=30; #количество копий


/usr/bin/curl https://freemyip.com/update?token=${_TOKEN=}&domain=${_DOMAIN}

crontab -l > /etc/_script/cron_${_DOMAIN}


mkdir /tmp/${fname}
cp -r /etc /tmp/${fname}/


mega-login ${_MEGA_USER}  ${_MEGA_PASS}

if ! [ -d ${LOCAL_BACKUPS_DIR} ]; then
echo "[$(date +%F" "%T)] -- No directory"
mkdir ${LOCAL_BACKUPS_DIR}
fi


tar cfz ${LOCAL_BACKUPS_DIR}/${fname}.tar.gz /tmp/$fname
rm -r /tmp/${fname}


#Create base backups directory in the mega- cloud
[ -z "$(mega-ls /${CLOUD_BACKUPS_DIR})" ] && mega-mkdir /${CLOUD_BACKUPS_DIR}

#Upload backups
#Remove old backups
echo "[$(date +%F" "%T)] -- Start remove $USER cloud backups:"
   while [ $(mega-ls  /${CLOUD_BACKUPS_DIR} |  grep -E "${NAMEARH}.tar.gz" | wc -l) -gt ${BACKUP_COUNT} ]
     do
        TO_REMOVE=$(mega-ls  /${CLOUD_BACKUPS_DIR} | grep -E "${NAMEARH}.tar.gz" | sort | head -n 1)
        echo "[$(date +%F" "%T)] -- Remove file: mega-:$TO_REMOVE"
        mega-rm /${CLOUD_BACKUPS_DIR}/${TO_REMOVE}
     done

echo "[$(date +%F" "%T)] -- Stop remove $USER cloud backups"
echo "[$(date +%F" "%T)] -- Start upload $USER backups:"

mega-cd  /${CLOUD_BACKUPS_DIR}

     FILES=$(/usr/bin/find  ${LOCAL_BACKUPS_DIR}  -type f -name "*.tar.gz"  | sort );
     for FILE in ${FILES}; do
         FILENAME=${FILE##*/}
#         echo "[$(date +%F" "%T)] -- Upload: $FILE"
         mega-put -c "${LOCAL_BACKUPS_DIR}/${FILENAME}" "/${CLOUD_BACKUPS_DIR}/"
     done
echo "[$(date +%F" "%T)] -- Stop upload $USER backups"
echo "[$(date +%F" "%T)]"

rm -r  ${LOCAL_BACKUPS_DIR}
mega-logout
