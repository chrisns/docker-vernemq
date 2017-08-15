#!/usr/bin/env bash

# if config has been mounted as a volume copy that in
if [ -f "/data/vm.args" ]; then
  cp -v /data/vm.args /etc/vernemq/
fi

if [ -f "/data/vm.args" ]; then
  cp -v /data/vm.args /etc/vernemq/
fi

if [ -f "/data/vernemq.conf" ]; then
  cp -v /data/vernemq.conf /etc/vernemq/
fi

# if acl has been mounted as a volume symlink it in
if [ -f "/data/vmq.acl" ]; then
  ln -svf /data/vmq.acl /etc/vernemq/vmq.acl
fi

# if passwd has been mounted as a volume symlink it in
if [ -f "/data/vmq.passwd" ]; then
  ln -svf /data/vmq.passwd /etc/vernemq/vmq.passwd
fi


# slow down startup
sleep 45

IP_ADDRESS=$(awk 'FNR==NR{a[$1];next}($1 in a){print}'  <(getent hosts $(hostname) | awk '{ print $1 }') <(getent hosts tasks.${PEER_DISCOVERY_NAME} | awk '{ print $1 }'))

echo found ${IP_ADDRESS}

# if we have a PEER_DISCOVERY_NAME we can make a better guess at the right IP to use
if env | grep -q "PEER_DISCOVERY_NAME"; then
  IP_ADDRESS=$(getent hosts $(hostname) | grep $(getent hosts tasks.${PEER_DISCOVERY_NAME} | head -n 1 |  cut -d"." -f1-3). | awk '{print $1}')
  echo found ${IP_ADDRESS} instead
fi


# Ensure correct ownership and permissions on volumes
chown vernemq:vernemq /var/lib/vernemq /var/log/vernemq
chmod 755 /var/lib/vernemq /var/log/vernemq

# Ensure the Erlang node name is set correctly
sed -i.bak "s/VerneMQ@127.0.0.1/VerneMQ@${IP_ADDRESS}/" /etc/vernemq/vm.args

sed -i '/########## Start ##########/,/########## End ##########/d' /etc/vernemq/vernemq.conf

echo "########## Start ##########" >> /etc/vernemq/vernemq.conf

env | grep DOCKER_VERNEMQ | grep -v DISCOVERY_NODE | cut -c 16- | tr '[:upper:]' '[:lower:]' >> /etc/vernemq/vernemq.conf

echo "erlang.distribution.port_range.minimum = 9100" >> /etc/vernemq/vernemq.conf
echo "erlang.distribution.port_range.maximum = 9109" >> /etc/vernemq/vernemq.conf
echo "listener.tcp.default = 0.0.0.0:1883" >> /etc/vernemq/vernemq.conf
echo "listener.ws.default = 0.0.0.0:8080" >> /etc/vernemq/vernemq.conf
echo "listener.vmq.clustering = ${IP_ADDRESS}:44053" >> /etc/vernemq/vernemq.conf
echo "listener.http.default = 0.0.0.0:8888" >> /etc/vernemq/vernemq.conf

echo "listener.tcp.proxy_protocol = on" >> /etc/vernemq/vernemq.conf
echo "listener.ws.proxy_protocol = on" >> /etc/vernemq/vernemq.conf
echo "listener.http.proxy_protocol = on" >> /etc/vernemq/vernemq.conf

echo "########## End ##########" >> /etc/vernemq/vernemq.conf

# Check configuration file
su - vernemq -c "/usr/sbin/vernemq config generate 2>&1 > /dev/null" | tee /tmp/config.out | grep error

if [ $? -ne 1 ]; then
    echo "configuration error, exit"
    echo "$(cat /tmp/config.out)"
    exit $?
fi

pid=0

# SIGUSR1-handler
siguser1_handler() {
    echo "stopped"
}

# SIGTERM-handler
sigterm_handler() {
    if [ $pid -ne 0 ]; then
        # this will stop the VerneMQ process
        vmq-admin cluster leave node=VerneMQ@${IP_ADDRESS} -k > /dev/null
        while [[ -d /proc/${pid} ]]
        do
          echo "waiting for clean shutdown"
          sleep 1
        done
        echo "shutdown cleanly"
    fi
    exit 143; # 128 + 15 -- SIGTERM
}

# setup handlers
# on callback, kill the last background process, which is `tail -f /dev/null`
# and execute the specified handler
trap 'kill ${!}; siguser1_handler' SIGUSR1
trap 'kill ${!}; sigterm_handler' SIGTERM

/usr/sbin/vernemq start
pid=$(vernemq getpid)

if env | grep -q "PEER_DISCOVERY_NAME"; then
    FIRST_PEER=$(getent hosts tasks.${PEER_DISCOVERY_NAME} | awk '{ print $1 }' | sort -V | grep -v ${IP_ADDRESS} | head -n 1)
    wait-for-it.sh -t 120 ${IP_ADDRESS}:44053 ${FIRST_PEER}:44053 && vmq-admin cluster join discovery-node=VerneMQ@${FIRST_PEER}
fi

tail -f /var/log/vernemq/console.log