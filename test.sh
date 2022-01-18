#!/bin/bash
set -e

test "$UID" = "0" || (echo "this script should be run as root" && exit 1)

HOSTNAME="testvm"
USERNAME="ubuntu"
PLAIN_TEXT_PASSWORD='password'
SSH_FORWARD_PORT="2222"

QEMU_HEADLESS="true" # set to "false" to display qemu window (requires X)

if lsof -i -P -n | grep LISTEN | grep -w $SSH_FORWARD_PORT; then
    echo "ERROR: port $SSH_FORWARD_PORT already in use"
    exit 1
fi

function cleanup() {
    if [ -f "qemu.pid" ]; then
        echo "killing qemu pid=$(cat qemu.pid)"
        kill -9 "$(cat qemu.pid)" || true
    fi
    kill -9 "$SSH_AGENT_PID" || true
}
trap cleanup EXIT

rm -f vm-testkey
ssh-keygen -b 3072 -t rsa -f vm-testkey -q -N "" -C "rsa-testkey"
PUBLIC_SSH_KEY="$(cat vm-testkey.pub)"
eval "$(ssh-agent -s)"
ssh-add vm-testkey

if ! [ -f "focal-server-cloudimg-amd64.img" ]; then
    wget http://cloud-images.ubuntu.com/focal/current/focal-server-cloudimg-amd64.img
fi
echo "f203162f0fb2a1f607547f479e57b7f9544c485859f3a8758eb89c0dd49b3bc0 *focal-server-cloudimg-amd64.img" | shasum -a 256 --check

qemu-img create -b focal-server-cloudimg-amd64.img -f qcow2 -F qcow2 "$HOSTNAME.img" 10G

PASSWD="$(openssl passwd -6 "$PLAIN_TEXT_PASSWORD")"
cat <<EOF > user-data
#cloud-config

users:
- name: $USERNAME
  passwd: $PASSWD
  lock_passwd: false
  ssh_authorized_keys:
  - $PUBLIC_SSH_KEY
  sudo: ['ALL=(ALL) NOPASSWD:ALL']
  shell: /bin/bash
EOF

cat > meta-data <<EOF
instance-id: $HOSTNAME
local-hostname: $HOSTNAME
EOF

# bundle the above two files into an iso
echo bundling metadata
rm -f cidata.iso
genisoimage \
   -output cidata.iso \
   -input-charset utf-8 \
   -volid cidata \
   -joliet \
   -rock \
   user-data meta-data

if [ "$QEMU_HEADLESS" = "true" ]; then
    NOGRAPHICS="-nographic"
else
    NOGRAPHICS=""
fi

cat > qemu.cmd <<EOF
qemu-system-x86_64 \
   -nodefaults \
   -device VGA \
   -m 8192 \
   -hda "$HOSTNAME.img" \
   -cdrom cidata.iso \
   $NOGRAPHICS \
   -netdev user,id=mynet0,hostfwd=tcp::$SSH_FORWARD_PORT-:22 -device e1000,netdev=mynet0 &
   echo \$! > qemu.pid
EOF

cwd="$(pwd)"
if [ "$QEMU_HEADLESS" = "true" ]; then
    /bin/sh -c "cd $cwd && bash qemu.cmd" &
else
    test -n "$SUDO_USER" || (echo "SUDO_USER must be set when running headless" && exit 1)
    /bin/sh -c "export XAUTHORITY=/home/$SUDO_USER/.Xauthority && cd $cwd && bash qemu.cmd" &
fi

waituntil="$(( "$(date +%s)" + 300 ))"
while true; do
    set +e
    SSH_HOSTNAME="$(ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -p $SSH_FORWARD_PORT $USERNAME@127.0.0.1 hostname)"
    set -e
    echo "ssh hostname returned: $SSH_HOSTNAME"
    if [ "$SSH_HOSTNAME" = $HOSTNAME ]; then
        echo "connection made, breaking loop"
        break
    fi
    now="$(date +%s)"
    if [ "$now" -gt "$waituntil" ]; then
        echo "failed to connect to VM"
        exit 1
    fi
	timer_remaining="$(( "$waituntil" - "$now" ))"
    echo "sleeping 10 seconds before retrying; $timer_remaining seconds left before giving up"
    sleep 10
done

scp -P $SSH_FORWARD_PORT -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null test-inside.vm $USERNAME@127.0.0.1:.
ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -p $SSH_FORWARD_PORT $USERNAME@127.0.0.1 "chmod +x ./test-inside.vm && sudo ./test-inside.vm; echo exit_code=\$?" | tee output.txt

if ! tail -n 1 output.txt | grep 'exit_code=[0-9]\+' >/dev/null; then
    echo "ERROR: failed to extract exit_code"
    exit 1
fi
exit_code=$(tail -n 1 output.txt | cut -d "=" -f2)

echo "test.sh exiting with exit_code=$exit_code"
exit "$exit_code"
