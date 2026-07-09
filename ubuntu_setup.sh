#!/bin/bash

# That is all root user operations
if [ "$(id -u)" -ne 0 ]; then
    echo "This script must be run as root" 1>&2
    exit 1
fi

# less words
cd /etc/update-motd.d/ && chmod -x 10-help-text 50-motd-news 91-release-upgrade

[ -n "$(swapon --show)" ] && echo 'Swap exists' || {
    echo 'No swap file detected - adding one'
    # add swap, ~twice of the size of RAM
    RAM_SIZE=`free -b | awk '/Mem:/ {print $2 / 1024 / 1024 / 1024}'`
    SWAP_SIZE=$(printf "%.0f" $(echo "$RAM_SIZE * 2 + 0.5" | bc))
    swapon --show # status quo
    free --giga -h #shows the RAM
    fallocate -l "${SWAP_SIZE}G" /swapfile
    chmod 600 /swapfile
    mkswap /swapfile
    swapon /swapfile
    swapon --show
    echo "/swapfile    none    swap    sw    0   0" >> /etc/fstab
}

echo "alias glances='glances --disable-bg'" >> ~/.bashrc
dpkg-reconfigure tzdata # adjust timezone

# Unattended upgrades
systemctl enable unattended-upgrades

cat <<\EOF > /etc/apt/apt.conf.d/50unattended-upgrades
Unattended-Upgrade::Allowed-Origins {
        "${distro_id}:${distro_codename}";
        "${distro_id}:${distro_codename}-security";
        "${distro_id}ESMApps:${distro_codename}-apps-security";
        "${distro_id}ESM:${distro_codename}-infra-security";
        "Docker:${distro_codename}";
};

Unattended-Upgrade::Package-Blacklist {
};

Unattended-Upgrade::DevRelease "false";
Unattended-Upgrade::AutoFixInterruptedDpkg "false";
Unattended-Upgrade::Remove-Unused-Dependencies "false";
Unattended-Upgrade::Remove-Unused-Kernel-Packages "false";
Unattended-Upgrade::MinimalSteps "true";
Unattended-Upgrade::SyslogEnable "true";
Unattended-Upgrade::SyslogFacility "daemon";
Unattended-Upgrade::Verbose "true";
Dpkg::Options {
   "--force-confdef";
   "--force-confold";
};
EOF
systemctl restart unattended-upgrades

[[ " $* " == *" -keep-ipv6 "* ]] && { echo "Leaving IPv6 as is"; } || {
cat <<EOF >> /etc/sysctl.d/99-no_ipv6.conf
net.ipv6.conf.all.disable_ipv6 = 1
net.ipv6.conf.default.disable_ipv6 = 1
EOF
service procps force-reload
}

# add automatic reboot at the night time
crontab -l | { cat; echo "$((RANDOM % 60)) $((2 + RANDOM % 4)) * * * /bin/sh -c '[ -f /var/run/reboot-required ] && sudo shutdown -r now'"; } | crontab -
crontab -l

[[ " $* " == *" -no-ssh "* ]] && { echo "Leaving ssh config as is"; } || {
    # changing ssh port
    new_ssh_port=$(shuf -i 1025-32875 -n 1)
    
    echo "NOTE new SSH port: $new_ssh_port"
    read -p "Press Enter to continue or Ctrl+C to abort"
    
    cp /etc/ssh/sshd_config /etc/ssh/sshd_config.bak
    sed -i "s/^Port.*/Port $new_ssh_port/" /etc/ssh/sshd_config
    sed -i "s/^\s*#*\s*Port\s*.*/Port $new_ssh_port/" /etc/ssh/sshd_config
    grep Port /etc/ssh/sshd_config
    
    read -p "Verify that port is valid and press Enter"
    
    systemctl restart ssh.socket sshd
}

apt update && apt upgrade -y
apt install -y vim monit

# export OVERRIDE_OBSERVANCE_TOOLS='btop htop'
apt install -y ${OVERRIDE_OBSERVANCE_TOOLS:-btop glances}


echo "set ts=4 sw=4" >> ~/.vimrc
echo "Changing default editor:"
sudo update-alternatives --config editor

echo "Done."
