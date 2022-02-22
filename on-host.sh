#!/bin/sh
set -ex

docker run --rm -ti --privileged --name kind-test -d kindest/node:v1.21.1
sleep 1
docker exec -ti kind-test /bin/sh -c 'hostname'
docker exec -ti kind-test /bin/sh -c 'service --status-all'

data="$(echo '[Unit]
Description=repro service
After=network.target
StartLimitIntervalSec=0

[Service]
Type=simple
Restart=always
RestartSec=1
User=root
ExecStart=/bin/sh -c '\''while true; do echo c2F5IHRoaXMK | base64 -d; sleep 5; done'\''

[Install]
WantedBy=multi-user.target' | base64 -w 0)"

echo $data
docker exec -ti kind-test /bin/sh -c "echo $data | base64 -d > /etc/systemd/system/repro.service"

docker exec -ti kind-test /bin/sh -c 'systemctl enable repro'
sleep 1

docker exec -ti kind-test /bin/sh -c 'systemctl start repro'
sleep 1

docker exec -ti kind-test /bin/sh -c 'systemctl status repro' > /tmp/repro.log
sleep 1

if ! grep "say this" /tmp/repro.log > /dev/null; then
    echo "say this not found in log"
    exit 1
fi
