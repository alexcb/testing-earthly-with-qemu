#!/bin/bash
set -e

test "$UID" = "0" || (echo "this script should be run as root" && exit 1)

HOSTNAME="testvm"
USERNAME="ubuntu"
PLAIN_TEXT_PASSWORD='password'
SSH_FORWARD_PORT="2222"

QEMU_HEADLESS="true" # set to "false" to display qemu window (requires X)
KEEP_QEMU="true"

DRIVESIZE="40G"
MEMORY="8192"
NUM_CORES="4"

if lsof -i -P -n | grep LISTEN | grep -w $SSH_FORWARD_PORT; then
    echo "ERROR: port $SSH_FORWARD_PORT already in use"
    exit 1
fi

test "$NUM_CORES" -le "$(nproc)"

function cleanup() {
    if [ "$KEEP_QEMU" = "true" ]; then
        echo "exiting without cleanup; keeping qemu instance running"
    else
        if [ -f "qemu.pid" ]; then
            echo "killing qemu pid=$(cat qemu.pid)"
            kill -9 "$(cat qemu.pid)" || true
        fi
        kill -9 "$SSH_AGENT_PID" || true
    fi
}
trap cleanup EXIT

#rm -f vm-testkey
if [ ! -f vm-testkey ]; then 
  ssh-keygen -b 3072 -t rsa -f vm-testkey -q -N "" -C "rsa-testkey"
fi
PUBLIC_SSH_KEY="$(cat vm-testkey.pub)"
eval "$(ssh-agent -s)"
ssh-add vm-testkey

ubuntu_version="hirsute"

# import UEC Image Automatic Signing Key <cdimage@ubuntu.com>
echo "e48ac81ab34b318fe757e94a707e9125af77abda338ec8886e327fd260ff74f4 *ubuntu-pub-key.gpg" | shasum -a 256 --check
gpg --always-trust --import ubuntu-pub-key.gpg
(echo trust &echo 5 &echo y &echo quit) | gpg --command-fd 0 --edit-key D2EB44626FDDC30B513D5BB71A5D6C4C7DB87C81

img="unknown"

if [ "$ubuntu_version" = "focal" ]; then
    mkdir -p focal
    cd focal
    if ! [ -f "focal-server-cloudimg-amd64.img" ]; then
        wget http://cloud-images.ubuntu.com/focal/20220111/focal-server-cloudimg-amd64.img
        wget http://cloud-images.ubuntu.com/focal/20220111/SHA256SUMS
        wget http://cloud-images.ubuntu.com/focal/20220111/SHA256SUMS.gpg
    fi
    gpg --verify SHA256SUMS.gpg SHA256SUMS
    cat SHA256SUMS | grep focal-server-cloudimg-amd64.img | shasum -a 256 --check
    cd ..
    img=focal/focal-server-cloudimg-amd64.img
fi

if [ "$ubuntu_version" = "hirsute" ]; then
    mkdir -p hirsute
    cd hirsute
    if ! [ -f "hirsute-server-cloudimg-amd64.img" ]; then
        wget http://cloud-images.ubuntu.com/hirsute/20220112/hirsute-server-cloudimg-amd64.img
        wget http://cloud-images.ubuntu.com/hirsute/20220112/SHA256SUMS
        wget http://cloud-images.ubuntu.com/hirsute/20220112/SHA256SUMS.gpg
    fi
    gpg --verify SHA256SUMS.gpg SHA256SUMS
    cat SHA256SUMS | grep hirsute-server-cloudimg-amd64.img | shasum -a 256 --check
    cd ..
    img=hirsute/hirsute-server-cloudimg-amd64.img
fi

qemu-img create -b "$img" -f qcow2 -F qcow2 "$HOSTNAME.img" "$DRIVESIZE"

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

ENABLE_KVM="-enable-kvm"

cat > qemu.cmd <<EOF
qemu-system-x86_64 \
   -nodefaults \
   -device VGA \
   -m "$MEMORY" \
   -smp "$NUM_CORES" \
   -hda "$HOSTNAME.img" \
   -cdrom cidata.iso \
   -cpu max \
   $NOGRAPHICS \
   $ENABLE_KVM \
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


if [ -n "$DOCKERHUB_MIRROR_USERNAME" ] && [ -n "$DOCKERHUB_MIRROR_PASSWORD" ]; then
    echo "copying DOCKERHUB_MIRROR_USERNAME and DOCKERHUB_MIRROR_PASSWORD values to VM"
    ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -p $SSH_FORWARD_PORT $USERNAME@127.0.0.1 "echo $DOCKERHUB_MIRROR_USERNAME > ~/DOCKERHUB_MIRROR_USERNAME && echo $DOCKERHUB_MIRROR_PASSWORD > ~/DOCKERHUB_MIRROR_PASSWORD"
else
    echo "failed to setup dockerhub mirror, did you sudo -E?" && exit 1
fi

ENABLE_CGROUP_V2="true"
if [ -n "$ENABLE_CGROUP_V2" ]; then
    echo enabling cgroups v2
    ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -p $SSH_FORWARD_PORT $USERNAME@127.0.0.1 "who -b" | tee /tmp/current-boot-before-cgroup-setup
    
    scp -P $SSH_FORWARD_PORT -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null setup-cgroups-v2.sh $USERNAME@127.0.0.1:.
    ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -p $SSH_FORWARD_PORT $USERNAME@127.0.0.1 "chmod +x ./setup-cgroups-v2.sh && sudo ./setup-cgroups-v2.sh; echo exit_code=\$?" | tee output.txt
    
    set +e
    while true; do
        sleep 15
        ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -p $SSH_FORWARD_PORT $USERNAME@127.0.0.1 "who -b" | tee /tmp/current-boot-after-cgroup-setup
        if grep "system boot" /tmp/current-boot-after-cgroup-setup; then 
            if ! diff /tmp/current-boot-before-cgroup-setup /tmp/current-boot-after-cgroup-setup; then
                echo "server has rebooted"
                break
            fi
        fi
    done
    set -e
fi

scp -P $SSH_FORWARD_PORT -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null test-inside.vm $USERNAME@127.0.0.1:.
ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -p $SSH_FORWARD_PORT $USERNAME@127.0.0.1 "chmod +x ./test-inside.vm && sudo ./test-inside.vm; echo exit_code=\$?" | tee output.txt

if ! tail -n 1 output.txt | grep 'exit_code=[0-9]\+' >/dev/null; then
    echo "ERROR: failed to extract exit_code"
    exit 1
fi
exit_code=$(tail -n 1 output.txt | cut -d "=" -f2)

if [ "$KEEP_QEMU" = "true" ]; then

    echo "to access the qemu vm, run:"
    echo "  eval \"\$(ssh-agent -s)\""
    echo "  ssh-add vm-testkey"
    echo "  ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -p $SSH_FORWARD_PORT $USERNAME@127.0.0.1" 

fi

echo "test.sh exiting with exit_code=$exit_code"
exit "$exit_code"


# TO enable cgroups v2
# based on some details in https://rootlesscontaine.rs/getting-started/common/cgroup2/

# edit /etc/default/grub
# and add 
#     GRUB_CMDLINE_LINUX="systemd.unified_cgroup_hierarchy=1"
# and possibly:
#     GRUB_CMDLINE_LINUX="systemd.unified_cgroup_hierarchy=1 cgroup_no_v1=all"
# but this still shows v1 running.
#
# if cgroups v2 is not enabled, this will fail:
#     ls /sys/fs/cgroup/cgroup.controllers
#
# to setup cgroups v2, edit /etc/default/grub
# and add 
#     GRUB_CMDLINE_LINUX="systemd.unified_cgroup_hierarchy=1"
#
# then run
#     update-grub && reboot now
#
# Once back inside the VM, run:
#     ls /sys/fs/cgroup/cgroup.controllers
# to verify cgroups v2 is working
#
#
#     sudo docker run --rm alpine /bin/sh -c 'while true; do whoami | md5sum; done'  # to simulate the load in one session
#     systemd-cgtop | grep -i docker # run this in another session
# which should show:
#  system.slice/docker-7fdc340fa3594176db1ef0732e52535c4a0f2c16f1fc820b868dccf4971b0567.scope       3      -   528.0K        -        -
#  system.slice/docker-d7afde6c5166101c7c9e939662b93101d2dabfab3222138f4e954528fa306a41.scope      13      -    97.9M        -        -
#  system.slice/docker.service    
# if it were on cgroup v1, it would instead show:
#  docker/917bc385b362642b4f3fade6afda3f88294e5b201edcf44a5e2efbf2cd63ca21
#
# Next with earthly, under cgroup v2 I was able to see
#  system.slice/docker-d7afde6c5166101c7c9e939662b93101d2dabfab3222138f4e954528fa306a41.scope/buildkit

#
#
# running unit tests via go
# 
# apt-get install build-essential
# 
# wget https://go.dev/dl/go1.17.6.linux-amd64.tar.gz
# rm -rf /usr/local/go && tar -C /usr/local -xzf go1.17.6.linux-amd64.tar.gz
#
# go test ./...
# go test ./util/containerutil/... -test.run="TestFrontendNew$" -v

