#!/bin/bash
set -e
echo "I am running on $(hostname)"

test "$UID" = "0" || (echo "this script should be run as root" && exit 1)

if ls /sys/fs/cgroup/cgroup.controllers; then
    echo "cgroups v2 is installed"
    exit 0
fi

mv /etc/default/grub /etc/default/grub.bkup
cat > /etc/default/grub <<EOF
GRUB_DEFAULT=0
GRUB_TIMEOUT_STYLE=hidden
GRUB_TIMEOUT=0
GRUB_DISTRIBUTOR=\`lsb_release -i -s 2> /dev/null || echo Debian\`
GRUB_CMDLINE_LINUX_DEFAULT="quiet splash"
GRUB_CMDLINE_LINUX="systemd.unified_cgroup_hierarchy=1"
EOF

update-grub
reboot now

## for apt to be noninteractive
#export DEBIAN_FRONTEND noninteractive
#export DEBCONF_NONINTERACTIVE_SEEN true
#
#apt-get update
#apt-get install -y \
#    ca-certificates \
#    curl \
#    gnupg \
#    lsb-release
#
#curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
#
#echo \
#  "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu \
#  $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
#
#apt-get update
#apt-get install -y docker-ce docker-ce-cli containerd.io
#
#docker run hello-world
#
#usermod -aG docker ubuntu
#
#wget https://github.com/earthly/earthly/releases/latest/download/earthly-linux-amd64 -O /usr/local/bin/earthly && chmod +x /usr/local/bin/earthly && /usr/local/bin/earthly bootstrap --with-autocomplete
#
#earthly github.com/earthly/hello-world+hello


# TO enable cgroups v2
# based on some details in https://rootlesscontaine.rs/getting-started/common/cgroup2/
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

