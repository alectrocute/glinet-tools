log() {
  LINE="network-watchdog $1"
  logger $LINE
  echo $LINE
}

log "Checking to see if router has internet connectivity..."

wget -q --spider -T 40 https://google.com

if [ $? -eq 0 ]; then
  log "WAN appears to be online. Doing nothing..."
else
  log "WAN appears to be offline. Rebooting router..."
  reboot
fi
