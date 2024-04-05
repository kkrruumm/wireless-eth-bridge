#!/bin/sh

if [ $USER != "root" ]; then
    echo "Please execute this script as root."
    exit 1
fi

# Define our upstream DNS
dns="1.1.1.1"
# Define our ethernets address and netmask
ethip="10.0.1.1/24"
# Define our dhcp IP range and lease time
dhcp="10.0.1.2,10.0.1.254,24h"
# Define needed packages
packages="nftables dnsmasq"

# Figure out what package manager is on the system
for i in xbps-install apk apt dnf pacman
do
    if which $i ; then
        pm="$i"
        break
    fi
done

# Figure out what init the system is using
for i in rc-service systemctl sv
do
    if which $i ; then
        init="$i"
        break
    fi
done

if [ -z "$init" ]; then
    echo "Unrecoginzed init system. Cannot continue."
    exit 1
fi

cat <<-__EOF__
Available interfaces:

$(ls /sys/class/net)

__EOF__

echo "Enter the name of your wireless interface. (ctrl+c to cancel)"
read wireless
echo "Enter the name of your ethernet interface. (ctrl+c to cancel)"
read ethernet

# Install packages
case $pm in
    xbps-install)
        xbps-install -Sy $packages
        ;;
    apk)
        apk update && apk add $packages
        ;;
    apt)
        apt update && apt install -y $packages
        ;;
    dnf)
        dnf update && dnf install -y $packages
        ;;
    pacman)
        pacman -S --noconfirm $packages
        ;;
    *)
        echo "Unrecognized package manager. Checking if needed packages are installed anyway..."

        if ! which nft || ! which dnsmasq ; then
            echo "nftables and/or dnsmasq seem to be missing and the package manager is unrecognized. Cannot continue."
            exit 1
        else
            echo "nftables and dnsmasq found. Continuing..."
        fi
        ;;
esac

# Enable services and configure interface if iproute is being used
case $init in
    rc-service)
        rc-update add nftables && rc-update add dnsmasq
        rc-service nftables start

        if ! which ifupdown ; then
            cat <<__EOF__ > /etc/init.d/wirelessebridge
#!/sbin/openrc-run
command='ip addr add $ethip dev $ethernet && ip link set $ethernet up && rc-service dnsmasq restart' 
__EOF__

            chmod +x /etc/init.d/wirelessebridge
            rc-update add wirelessebridge
        fi
        ;;
    systemctl)
        systemctl enable nftables && systemctl enable dnsmasq
        systemctl start nftables

        if ! which ifupdown ; then
            cat <<__EOF__ > /etc/systemd/system/wirelessebridge.service
Description=Configure wireless eth bridge interface
        
[Service]
Type=oneshot
ExecStart=/bin/sh -c 'ip addr add $ethip dev $ethernet && ip link set $ethernet up && systemctl restart dnsmasq'
        
[Install]
WantedBy=multi-user.target
__EOF__

            systemctl enable wirelessebridge
        fi
        ;;
    sv)
        ln -s /etc/sv/nftables /var/service/
        ln -s /etc/sv/dnsmasq  /var/service/

        if ! which ifupdown ; then
            mkdir /etc/sv/wirelessebridge
            cat <<__EOF__ > /etc/sv/wirelessebridge/run
#!/bin/sh
exec 2>&1
[ ! -e /tmp/wirelessebridge ] && ip addr add $ethip dev $ethernet && ip link set $ethernet up
[ ! -e /tmp/wirelessebridge ] && sv restart dnsmasq && touch /tmp/wirelessebridge
__EOF__

            chmod +x /etc/sv/wirelessebridge/run
            ln -s /etc/sv/wirelessebridge /var/service/
        fi
        ;;
esac

# If ifupdown is found on the system, we can/should use that instead of iproute commands.
if which ifupdown ; then
    cat <<__EOF__ >> /etc/network/interfaces
    auto $ethernet
    allow-hotplug $ethernet
    iface $ethernet inet static
        address $ethip
        gateway $ethip
__EOF__
fi

# Create nat table
nft add table ip nat
# Create postrouting chain
nft add chain ip nat postrouting '{type nat hook postrouting priority 100; policy accept;}'
# Create rule
nft add rule ip nat postrouting oifname "$wireless" masquerade

if grep "table inet filter" /etc/nftables.conf || grep "table inet filter" /etc/nftables.nft ; then
    # Allow forwarding
    nft add chain inet filter forward '{type filter hook forward priority 0; policy accept;}'
    # Allow input from eth
    nft add rule inet filter input iifname "$ethernet" accept
fi

# Save active nftables config
if [ -e /etc/nftables.nft ] ; then
    rm /etc/nftables.nft
    nft list ruleset >> /etc/nftables.nft
else
    if [ -e /etc/nftables.conf ] ; then
        rm /etc/nftables.conf
    fi
    nft list ruleset >> /etc/nftables.conf
fi

# Enable ipv4 forwarding
if ! grep "net.ipv4.ip_forward=1" /etc/sysctl.conf ; then
    echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf
elif grep "#net.ipv4.ip_forward=1" /etc/sysctl.conf ; then
    sed -i -e 's/#net.ipv4.ip_forward=1/net.ipv4.ip_forward=1/g' /etc/sysctl.conf
fi

cat <<__EOF__ >> /etc/dnsmasq.conf
interface=$ethernet
bind-interfaces
server=$dns
domain-needed
bogus-priv
dhcp-range=$dhcp
__EOF__

echo "Done. Please reboot."
