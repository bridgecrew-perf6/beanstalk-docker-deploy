#!/bin/bash -xe

# This script needs you to set a new ENV var in your Beanstalk environment.

# netvfy_username, netvfy_password, netvfy_netdesc, netvfy_node_prefix

NET_DESC="$netvfy_netdesc"
DEST_SCRIPT="/usr/local/sbin/netvfy-agent"

function build_install_agent() {
  yum -y install git go
  git clone https://github.com/netvfy/go-netvfy-agent.git /tmp/go-netvfy-agent
  cd /tmp/go-netvfy-agent
  make netvfy-agent
  mv netvfy-agent /usr/local/sbin/
}

function add_node_to_network() {
  EC2_INSTANCE_ID="`wget -q -O - http://169.254.169.254/latest/meta-data/instance-id`"
  PASSWORD="$netvfy_password"
  EMAIL="$netvfy_username"
  HOST="api.netvfy.com"
  IP_SUFFIX="`ip -4 addr show eth0 | grep inet | awk -F / {'print $1'} | cut -c 15-`"
  NODE_DESC="$netvfy_node_prefix-$IP_SUFFIX-$EC2_INSTANCE_ID" # `mktemp -u XXXXXXXXXX`
  APIKEY=$(curl -s -H 'Content-Type: application/json' -d '{"email":"'${EMAIL}'","password":"'${PASSWORD}'"}' \
    -X POST https://${HOST}/v1/client/newapikey | jq -r '.client.apikey')

  curl -s -i -H 'X-netvfy-email: '${EMAIL}'' -H 'X-netvfy-apikey: '${APIKEY}'' -H 'Content-Type: application/json' \
    -d '{"network_description":"'${NET_DESC}'", "description":"'${NODE_DESC}'"}' -X POST https://${HOST}/v1/node

  # get NET_UID
  NET_UID="$(curl -s -H 'X-netvfy-email: '${EMAIL}'' -H 'X-netvfy-apikey: '${APIKEY}'' https://${HOST}/v1/network | jq -r ".networks[] | select(.description==\"${NET_DESC}\").uid")"

  PROV_CODE=$(curl -s -H 'X-netvfy-email: '${EMAIL}'' -H 'X-netvfy-apikey: '${APIKEY}'' https://${HOST}/v1/node?network_uid=$NET_UID \
    | jq -r ".nodes[] | select(.description==\"$NODE_DESC\").provcode")

  $DEST_SCRIPT -k "$PROV_CODE" -n $NET_DESC

}

if [ ! -e $DEST_SCRIPT ]
then
  build_install_agent
fi

# grep -q $NET_DESC /root/.config/netvfy/nvagent.json
if [ -e /root/.config/netvfy/nvagent.json ]
then
  $DEST_SCRIPT -c $NET_DESC &
else
  add_node_to_network
  $DEST_SCRIPT -c $NET_DESC &
fi
