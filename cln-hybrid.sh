#!/bin/bash

# turn Core Lightning node hybrid mode on or off
# example: "cln-hybrid.sh on"

# command info
if [ $# -eq 0 ] || [ "$1" = "-h" ] || [ "$1" = "-help" ]; then
  echo "config script to turn Core Lighting hybrid mode on or off"
  echo "cln-hybrid.sh [status|on|off]"
  exit 1
fi

# find home directory based on node implementation
if [ -d "/mnt/hdd/mynode/pleb-vpn/" ]; then
  homedir="/mnt/hdd/mynode/pleb-vpn"
  execdir="/opt/mynode/pleb-vpn"
elif [ -f "/mnt/hdd/raspiblitz.conf" ]; then
  homedir="/mnt/hdd/app-data/pleb-vpn"
  execdir="/home/admin/pleb-vpn"
fi
plebVPNConf="${homedir}/pleb-vpn.conf"
source <(cat ${plebVPNConf} | sed '1d')

function setting() # FILE LINENUMBER NAME VALUE
{
  FILE=$1
  LINENUMBER=$2
  NAME=$3
  VALUE=$4
  settingExists=$(cat ${FILE} | grep -c "^${NAME}=")
  echo "# setting ${FILE} ${LINENUMBER} ${NAME} ${VALUE}"
  echo "# ${NAME} exists->(${settingExists})"
  if [ "${settingExists}" == "0" ]; then
    echo "# adding setting (${NAME})"
    sudo sed -i --follow-symlinks "${LINENUMBER}i${NAME}=" ${FILE}
  fi
  echo "# updating setting (${NAME}) with value(${VALUE})"
  sudo sed -i --follow-symlinks "s/^${NAME}=.*/${NAME}=${VALUE}/g" ${FILE}
}

status() {
  # show current Core Lightning status
  local webui="${1}"
  nodeName=$(sudo -u bitcoin lightning-cli getinfo | jq .alias | sed 's/\"//g')
  nodeID=$(sudo -u bitcoin lightning-cli getinfo | jq .id | sed 's/\"//g')
  address0Type=$(sudo -u bitcoin lightning-cli getinfo | jq .address[0].type | sed 's/\"//g')
  address0Port=$(sudo -u bitcoin lightning-cli getinfo | jq .address[0].port | sed 's/\"//g')
  address0=$(sudo -u bitcoin lightning-cli getinfo | jq .address[0].address | sed 's/\"//g')
  if [ "${clnhybrid}" = "on" ]; then
    address1Type=$(sudo -u bitcoin lightning-cli getinfo | jq .address[1].type | sed 's/\"//g')
    address1Port=$(sudo -u bitcoin lightning-cli getinfo | jq .address[1].port | sed 's/\"//g')
    address1=$(sudo -u bitcoin lightning-cli getinfo | jq .address[1].address | sed 's/\"//g')
    if [ "${webui}" = "1" ]; then
      echo "Alias='${nodeName}'
Node_ID='${nodeID}'
address0='${address0}'
address1='${address1}'
address0Type='${address0Type}'
address1Type='${address1Type}'" | tee ${execdir}/cln_hybrid_status.tmp
    else
      whiptail --title "Core Lightning hybrid status" --msgbox "
Alias = ${nodeName}
Hybrid Mode = ${clnHybrid}
Node ID = ${nodeID}
${address0Type} address: ${address0}:${address0Port}
${address1Type} address: ${address1}:${address1Port}
" 13 100
    fi
    exit 0
  else
    if [ "${webui}" = "1" ]; then
      echo "Alias='${nodeName}'
Node_ID='${nodeID}'
address0='${address0}'
address0Type='${address0Type}'" | tee ${execdir}/cln_hybrid_status.tmp
    else
      whiptail --title "Core Lightning status" --msgbox "
Alias = ${nodeName}
Hybrid Mode = ${clnHybrid}
Node ID = ${nodeID}
${address0Type} address: ${address0}:${address0Port}
" 12 100
    fi
    exit 0
  fi
}

on() {
  # enable hybrid mode
  if [ "${nodetype}" = "raspiblitz" ]; then
    source /mnt/hdd/raspiblitz.conf
  fi
  local isRestore="${1}"
  local webui="${2}"

  # check if plebvpn is on
  if ! [ "${plebvpn}" = "on" ]; then
    echo "error: turn on plebvpn before enabling hybrid mode"
    exit 1
  fi
  # check if CLN node is availabe
  if [ "${nodetype}" = "mynode" ]; then
    echo "error: no core lightning node found"
    exit 1
  elif [ "${nodetype}" = "raspiblitz" ]; then
    if ! [ "${cl}" = "on" ]; then
      echo "error: no core lightning node found"
      exit 1
    fi
  fi

  # get CLN port
  if [ ! -z "${clnport}" ]; then
    # skip if restoring
    if [ ! "${isRestore}" = "1" ]; then
      whiptail --title "Use Existing Port?" \
      --yes-button "Use Existing" \
      --no-button "Enter New Port" \
      --yesno "There is an existing port from a previous install. Do you want to re-use ${clnport} or enter a new one?" 10 80
      if [ $? -eq 1 ]; then
        keepport="0"
      else
        keepport="1"
      fi
    else
      keepport="1"
    fi
  else
    keepport="0"
  fi
  if [ "${keepport}" = "0" ]; then
    if [ "${nodetype}" = "raspiblitz" ]; then
      sudo touch /var/cache/raspiblitz/.tmp
      sudo chmod 777 /var/cache/raspiblitz/.tmp
      whiptail --title "Core Lightning Clearnet Port" --inputbox "Enter the clearnet port assigned to your Core Lightning node. If you don't have one, forward one from your VPS or contact your VPS provider to obtain one. (example: 9740)" 12 80 2>/var/cache/raspiblitz/.tmp
      clnport=$(cat /var/cache/raspiblitz/.tmp)
      # check to make sure port isn't already used by LND or WireGuard
      if [ "${clnport}" = "${lnport}" ] || [ "${clnport}" = "${wgport}" ]; then
        whiptail --title "Core Lightning Clearnet Port" --inputbox "ERROR: You must not use the same port as a previous service. Enter a different port than ${clnport}." 12 80 2>/var/cache/raspiblitz/.tmp
        clnport=$(cat /var/cache/raspiblitz/.tmp)
        if [ "${clnport}" = "${lnport}" ] || [ "${clnport}" = "${wgport}" ]; then
          echo "error: port must be different than other services"
          exit 1
        fi
      fi
      # add CLN port to pleb-vpn.conf  
      setting ${plebVPNConf} "2" "clnport" "'${clnport}'"
    else
      echo "ERROR: no port for CLN to enable hybrid mode."
      exit 1
    fi
  fi
  # configure firewall
  sudo ufw allow ${clnport} comment "CLN Port"
  # edit CLN config
  # Tor settings
  sectionName="Tor settings"
  echo "# ${sectionName} config ..."
  sectionLine=$(cat ${clnconffile} | grep -n "^\# ${sectionName}" | cut -d ":" -f1)
  echo "# sectionLine(${sectionLine})"
  insertLine=$(expr $sectionLine + 1)
  echo "# insertLine(${insertLine})"
  fileLines=$(wc -l ${clnconffile} | cut -d " " -f1)
  echo "# fileLines(${fileLines})"
  if [ ${fileLines} -lt ${insertLine} ]; then
    echo "# adding new line for inserts"
    echo "
  " | sudo tee -a ${clnconffile}
  fi
  echo "# sectionLine(${sectionLine})"
  setting ${clnconffile} ${insertLine} "always-use-proxy" "false"
  # Clearnet settings
  sectionName="Clearnet settings"
  echo "# ${sectionName} config ..."
  sectionExists=$(cat ${clnconffile} | grep -c "^\# ${sectionName}")
  echo "# sectionExists(${sectionExists})"
  if [ "${sectionExists}" == "0" ]; then
    echo "# adding section # Clearnet settings"
    echo "
# Clearnet settings
" | sudo tee -a ${clnconffile}
  fi
  sectionLine=$(cat ${clnconffile} | grep -n "^\# ${sectionName}" | cut -d ":" -f1)
  echo "# sectionLine(${sectionLine})"
  insertLine=$(expr $sectionLine + 1)
  echo "# insertLine(${insertLine})"
  fileLines=$(wc -l ${clnconffile} | cut -d " " -f1)
  echo "# fileLines(${fileLines})"
  if [ ${fileLines} -lt ${insertLine} ]; then
    echo "# adding new line for inserts"
    echo "
  " | sudo tee -a ${clnconffile}
  fi
  echo "# sectionLine(${sectionLine})"
  isBindaddr=$(cat ${clnconffile} | grep -c "bind-addr=0.0.0.0:")
  if [ ${isBindaddr} -eq 0 ]; then
    sudo sed -i "${insertLine}ibind-addr=0.0.0.0:${clnport}" ${clnconffile}
  else
    sudo sed -i "s/bind-addr=0\.0\.0\.0:.*/bind-addr=0\.0\.0\.0:${clnport}/" ${clnconffile}
  fi
  setting ${clnconffile} ${insertLine} "announce-addr" "${vpnIP}:${clnport}"

  # restart CLN (skip this step on restore but not if webui)
  if ! [ "${isRestore}" = "1" ]; then
    sudo systemctl restart lightningd.service
  fi
  if [ "${webui}" = "1" ]; then
    sudo systemctl restart lightningd.service
  fi
  # set cln-hybrid on in pleb-vpn.conf
  setting ${plebVPNConf} "2" "clnHybrid" "on"
  exit 0
}

off() {
  # disable hybrid mode
  # Tor settings
  sectionName="Tor settings"
  echo "# ${sectionName} config ..."
  sectionLine=$(cat ${clnconffile} | grep -n "^\# ${sectionName}" | cut -d ":" -f1)
  echo "# sectionLine(${sectionLine})"
  insertLine=$(expr $sectionLine + 1)
  echo "# insertLine(${insertLine})"
  fileLines=$(wc -l ${clnconffile} | cut -d " " -f1)
  echo "# fileLines(${fileLines})"
  if [ ${fileLines} -lt ${insertLine} ]; then
    echo "# adding new line for inserts"
    echo "
" | sudo tee -a ${clnconffile}
  fi
  echo "# sectionLine(${sectionLine})"
  setting ${clnconffile} ${insertLine} "always-use-proxy" "true"
  # Clearnet settings
  sectionName="Clearnet settings"
  echo "# ${sectionName} config ..."
  echo "removing Clearnet settings ..."
  sudo sed -i '/Clearnet settings/d' ${clnconffile}
  sudo sed -i '/bind-addr=0.0.0.0/d' ${clnconffile}
  sudo sed -i '/announce-addr/d' ${clnconffile}
  # configure firewall
  if [ ! "${clnport}" = "9736" ] && [ ! "${clnport}" = "9735" ]; then
    sudo ufw delete allow ${clnport}
  fi
  # restart CLN
  sudo systemctl restart lightningd.service
  # set cln-hybrid off in pleb-vpn.conf
  setting ${plebVPNConf} "2" "clnHybrid" "off"
  exit 0
}

case "${1}" in
  status) status "${2}" ;;
  on) on "${2}" "${3}" ;;
  off) off ;;
  *) echo "err=Unknown action: ${1}" ; exit 1 ;;
esac
