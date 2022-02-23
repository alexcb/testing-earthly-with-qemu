#!/bin/sh
set -ex

IMG="${IMG:-kindest/node:v1.21.1}"
echo "using IMG=$IMG"

docrun() {
  echo starting kind-test container
  docker run --privileged --name kind-test $EXTRA "$IMG" 2>&1 | tee /tmp/kind-test-systemd.log
  echo kind-test container finished
}

docrun &
sleep 1

finish() {
  echo "dumping kind-test logs"
  docker logs kind-test

  echo "dumping systemd log"
  cat /tmp/kind-test-systemd.log

  docker inspect kind-test | grep -C 10 entry
  if [ -z "$KEEP" ]; then
    docker rm --force kind-test
  fi
}
trap finish EXIT

timeout="30"
until="$(expr "$(date +%s)" + "$timeout")"
while true; do
  docker exec kind-test /bin/sh -c 'ps' > /tmp/systemd.test.logs
  set +e
  cat /tmp/systemd.test.logs | grep systemd | awk '{print $1}' | grep '^1$'
  code=$?
  set -e
  if [ "$code" -eq "0" ]; then
    echo "systemd has started in container"
    break
  fi
  if [ "$until" -lt "$(date +%s)" ]; then
    echo "systemd failed to start within $timeout seconds"
    exit 1
  fi
  sleep 1
done

docker exec kind-test /bin/sh -c 'hostname'

#docker exec kind-test /bin/sh -c 'busctl --list' # this also fails on cgroups-v1, but doesn't prevent it from working.

docker exec kind-test /bin/sh -c 'service --status-all'

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

docker exec kind-test /bin/sh -c "echo $data | base64 -d > /etc/systemd/system/repro.service"

docker exec kind-test /bin/sh -c 'systemctl enable repro'
sleep 1

docker exec kind-test /bin/sh -c 'systemctl start repro'
sleep 1

docker exec kind-test /bin/sh -c 'systemctl status repro' > /tmp/repro.log
sleep 1

if ! grep "say this" /tmp/repro.log > /dev/null; then
    echo "say this not found in log"
    exit 1
fi

echo "systemd via kindest/node works"
