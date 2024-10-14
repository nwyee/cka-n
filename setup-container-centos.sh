#!/bin/bash
# Script for setting up containerd on CentOS
# Based on https://kubernetes.io/docs/setup/production-environment/container-runtime

# changes March 14 2023: introduced $PLATFORM to support both amd64 and arm64

# setting MYOS variable
MYOS=$(hostnamectl | awk '/Operating/ { print $3 }')
OSVERSION=$(hostnamectl | awk '/Operating/ { print $4 }')
# Beta: building in ARM support
[ $(arch) = aarch64 ] && PLATFORM=arm64
[ $(arch) = x86_64 ] && PLATFORM=amd64

# Installing jq if not already installed
sudo yum install -y jq

if [ $MYOS = "CentOS" ] || [ $MYOS = "Red" ] || [ $MYOS = "AlmaLinux" ] || [ $MYOS = "Rocky" ]
then
    ### Setting up container runtime prerequisites
    cat <<- EOF | sudo tee /etc/modules-load.d/containerd.conf
    overlay
    br_netfilter
EOF

    sudo modprobe overlay
    sudo modprobe br_netfilter

    # Setup required sysctl params, these persist across reboots.
    cat <<- EOF | sudo tee /etc/sysctl.d/99-kubernetes-cri.conf
    net.bridge.bridge-nf-call-iptables  = 1
    net.ipv4.ip_forward                 = 1
    net.bridge.bridge-nf-call-ip6tables = 1
EOF

    # Apply sysctl params without reboot
    sudo sysctl --system

    # (Install containerd)
    # Getting rid of hard-coded version numbers
    CONTAINERD_VERSION=$(curl -s https://api.github.com/repos/containerd/containerd/releases/latest | jq -r '.tag_name')
    CONTAINERD_VERSION=${CONTAINERD_VERSION#v}
    wget https://github.com/containerd/containerd/releases/download/v${CONTAINERD_VERSION}/containerd-${CONTAINERD_VERSION}-linux-${PLATFORM}.tar.gz
    sudo tar xvf containerd-${CONTAINERD_VERSION}-linux-${PLATFORM}.tar.gz -C /usr/local

    # Configure containerd
    sudo mkdir -p /etc/containerd
    cat <<- TOML | sudo tee /etc/containerd/config.toml
version = 2
[plugins]
  [plugins."io.containerd.grpc.v1.cri"]
    [plugins."io.containerd.grpc.v1.cri".containerd]
      discard_unpacked_layers = true
      [plugins."io.containerd.grpc.v1.cri".containerd.runtimes]
        [plugins."io.containerd.grpc.v1.cri".containerd.runtimes.runc]
          runtime_type = "io.containerd.runc.v2"
          [plugins."io.containerd.grpc.v1.cri".containerd.runtimes.runc.options]
            SystemdCgroup = true
TOML

    RUNC_VERSION=$(curl -s https://api.github.com/repos/opencontainers/runc/releases/latest | jq -r '.tag_name')

    wget https://github.com/opencontainers/runc/releases/download/${RUNC_VERSION}/runc.${PLATFORM}
    sudo install -m 755 runc.${PLATFORM} /usr/local/sbin/runc

    # Restart containerd
    wget https://raw.githubusercontent.com/containerd/containerd/main/containerd.service
    sudo mv containerd.service /usr/lib/systemd/system/
    sudo systemctl daemon-reload
    sudo systemctl enable --now containerd
fi

# Disabling SELinux enforcement for containerd, as AppArmor is not used on CentOS
if command -v selinuxenabled &> /dev/null && selinuxenabled; then
    sudo setenforce 0
    sudo sed -i 's/^SELINUX=enforcing/SELINUX=permissive/' /etc/selinux/config
fi

# Confirm installation
touch /tmp/container.txt
exit
