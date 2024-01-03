#!/bin/bash

if [ ! -f /etc/debian_version ]; then
    echo "This script is currently only for Debian based systems."
    exit 1
fi

echo "Installing opifancontrol..."
echo ""
curl -s https://raw.githubusercontent.com/jamsinclair/opifancontrol/main/opifancontrol.sh -o /usr/local/bin/opifancontrol.sh
chmod +x /usr/local/bin/opifancontrol.sh

curl -s https://raw.githubusercontent.com/jamsinclair/opifancontrol/main/opifancontrol.conf -o /etc/opifancontrol.conf

curl -s https://raw.githubusercontent.com/jamsinclair/opifancontrol/main/opifancontrol.service -o /etc/systemd/system/opifancontrol.service

echo "Finished installing opifancontrol!"
echo ""
echo "Configure opifancontrol by editing /etc/opifancontrol.conf"
echo ""
echo Run the following command to enable the service to start on boot:
echo "    systemctl enable opifancontrol.service"
echo ""
echo Run the following command to start the service:
echo "    systemctl start opifancontrol.service"
echo ""
echo Run the following command to check the status of the service:
echo "    systemctl status opifancontrol.service"
echo ""
echo Run the following command to stop the service:
echo "    systemctl stop opifancontrol.service"
