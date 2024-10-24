# cron example (wg-watchdog.sh being this file):
# 58 0-7 * * * /root/wg-watchdog.sh

# start config
USERNAME='root'
PASSWORD='mypassword'
HOST='192.168.8.1'

WG_PEER_IP='12.123.14.2'
WG_GROUP_ID=123 # find in browser devtools while toggling wg on/off
WG_PEER_ID=456  # ^
# end config

log() {
  LINE="wg-watchdog $1"
  logger $LINE
  echo $LINE
}

log "Attempting to turn off and on WireGuard client (if needed)..."

# make sure dependencies are installed
if opkg status jq | grep -q 'Installed-Time'; then
  continue
else
  log "Installing jq package..."
  opkg install jq
  log "Finished installing jq package!"
fi

log "Checking to see if router has WAN connectivity..."

wget -q --spider -T 10 https://google.com

if [ $? -eq 0 ]; then
  log "Router has WAN connectivity!"
else
  log "Router does not have WAN connectivity. Exiting..."
  exit 1
fi

CURRENT_IP=$(curl -s 'https://icanhazip.com')

if [ "$CURRENT_IP" == "$WG_PEER_IP" ]; then
  log "VPN is working correctly, IP address is $CURRENT_IP!"
  log "Exiting watchdog script..."
  exit 1
else
  log "VPN is not working correctly, IP address is $CURRENT_IP which doesn't match $WG_PEER_IP. Restarting WireGuard..."
fi

log "Attempting to authenticate with GL.iNet web application..."

CHALLENGE_RESPONSE=$(curl -X POST \
  -H 'Content-Type: application/json' \
  -d '{"jsonrpc":"2.0","method":"challenge","params": {"username": "'$USERNAME'"},"id": 0}' \
  http://$HOST/rpc \
  -s)

ALG=$(jq -n "$CHALLENGE_RESPONSE" | jq '.result.alg' | tr -d '"')
SALT=$(jq -n "$CHALLENGE_RESPONSE" | jq '.result.salt' | tr -d '"')
NONCE=$(jq -n "$CHALLENGE_RESPONSE" | jq '.result.nonce' | tr -d '"')

CIPHER_PASSWORD=$(openssl passwd -1 -salt "$SALT" "$PASSWORD")

HASH=$(echo -n "$USERNAME:$CIPHER_PASSWORD:$NONCE" | md5sum | cut -d' ' -f1)

SID=$(curl -X POST \
  -H 'Content-Type: application/json' \
  -d '{"jsonrpc":"2.0","method":"login","params": {"username": "'$USERNAME'", "hash": "'$HASH'"},"id": 0}' \
  http://$HOST/rpc \
  -s |
  jq '.result.sid' |
  tr -d '"')

log "Finished authenticating with GL.iNet web application!"
log "Attempting to turn off WireGuard client..."

WIREGUARD_OFF_RESPONSE=$(curl -X POST \
  -H 'Content-Type: application/json' \
  -d '{"jsonrpc":"2.0","method":"call","params":["'$SID'","wg-client","stop", {}],"id": 0}' \
  http://$HOST/rpc \
  -s)

log $WIREGUARD_OFF_RESPONSE

log "Attempting to turn on WireGuard client..."

WIREGUARD_ON_RESPONSE=$(curl -X POST \
  -H 'Content-Type: application/json' \
  -d '{"jsonrpc":"2.0","method":"call","params":["'$SID'","wg-client","start",{"group_id":'$WG_GROUP_ID',"peer_id":'$WG_PEER_ID'}],"id":0}' \
  http://$HOST/rpc \
  -s)

log $WIREGUARD_ON_RESPONSE

log "Complete!"
