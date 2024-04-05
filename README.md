# wireless-eth-bridge
A simple shell script to turn a device into a wireless ethernet bridge using nftables, dnsmasq, and iproute or ifupdown.

If the system is not using ifupdown, iproute will be used instead.

This script has been tested on a Raspberry Pi 3b+ running Alpine Linux, a Dell Optiplex 3040 Micro running Alpine and Void Linux, and a Thinkpad t440s running Debian.

If all goes well, when connected to wifi, the device this script is ran on should provide an IP address and internet via its ethernet port to another device.

# Instructions
```
git clone https://github.com/kkrruumm/wireless-eth-bridge.git
cd wireless-eth-bridge
chmod +x setup-bridge.sh
sudo ./setup-bridge.sh
Follow on-screen steps
Done.
```

# Notes
If you would like to change the upstream DNS server, dhcp address range, lease time or otherwise, open this script in a text editor and modify the variables at the top of the script.

If the system uses a package manager this script is familiar with, it will install the necessary packages.

If the system uses a package manager this script is unfamiliar with, it will check the system for nftables and dnsmasq and attempt to continue.

At the moment, this script only supports Runit, OpenRC, and SystemD distros.
