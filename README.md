# opifancontrol

A simple PWM fan controller for Orange Pi boards (Only tested on an Orange Pi 5 Plus).

## Features

- Runs as a systemd service
- Automatically control the speed of a PWM fan based on the temperature of the CPU
- Configurable thresholds for fan speed and temperature
- Ramp up and ramp down delays to avoid rapid on/off switching of the fan

## Installation

### Prerequisites

Installed the [wiringOP](https://github.com/orangepi-xunlong/wiringOP) library. Check the [installation instructions](https://github.com/orangepi-xunlong/wiringOP#how-to-download-wiringop).

### Install via script

Run the following command to install the fan controller:

```bash
# Run again with sudo if you get permission errors
curl -sSL https://raw.githubusercontent.com/jamsinclair/opifancontrol/main/install.sh | bash
```

### Install manually

<summary>Install the fan controller manually.
<details>

1. Copy the `opifancontrol.sh` script to `/usr/local/bin/` and make it executable:

```bash
cp opifancontrol.sh /usr/local/bin/opifancontrol
chmod +x /usr/local/bin/opifancontrol
```

2. Copy the `opifancontrol.conf` file to `/etc/`:

```bash
cp opifancontrol.conf /etc/
```

3. Copy the `opifancontrol.service` file to `/etc/systemd/system/`:

```bash
cp opifancontrol.service /etc/systemd/system/
```

4. Enable the service:

```bash
systemctl enable opifancontrol.service
```
</details>
</summary>

## Configuration

The configuration file is located at `/etc/opifancontrol.conf`. The default configuration is:

```bash
# The GPIO pin to use for the fan. This is the wPi pin number, not the physical pin number.
# You can find the wPi pin number by running `gpio readall` on the Orange Pi.
FAN_GPIO_PIN=2

# TEMP_LOW, TEMP_MED, TEMP_HIGH are in degrees Celsius
# FAN_LOW, FAN_MED, FAN_HIGH are in percent of max fan speed, max 100.
# The fan will only be turned on if the temperature is above TEMP_LOW.
TEMP_LOW=50
FAN_LOW=75
TEMP_MED=65
FAN_MED=89
TEMP_HIGH=70
FAN_HIGH=100

# How frequently, in seconds, to poll the temperature data
TEMP_POLL_SECONDS=2

# To avoid rapid on/off switching, the fan will delay switching back on if it was recently turned off.
RAMP_UP_DELAY_SECONDS=15
# The ramp down delay is how long the fan will stay on after the temperature drops below the threshold.
RAMP_DOWN_DELAY_SECONDS=60

# The PWM range and clock are used to control the fan speed. You shouldn't need to change these unless you know what you're doing.
PWM_RANGE=1024
PWM_CLOCK=375
```

## Uninstallation

To uninstall the fan controller, first stop and disable the service:

```bash
systemctl stop opifancontrol.service
systemctl disable opifancontrol.service
```

Then remove the files:

```bash
rm /usr/local/bin/opifancontrol.sh
rm /etc/opifancontrol.conf
rm /etc/systemd/system/opifancontrol.service
```

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.
