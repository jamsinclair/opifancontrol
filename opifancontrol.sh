#!/bin/bash
OPIFANCONTROL_VERSION="1.0.1"

# Default values
TEMP_LOW=55
FAN_LOW=50
TEMP_MED=65
FAN_MED=75
TEMP_HIGH=70
FAN_HIGH=100
TEMP_POLL_SECONDS=2

RAMP_UP_DELAY_SECONDS=15
RAMP_DOWN_DELAY_SECONDS=60

FAN_GPIO_PIN=2
PWM_RANGE=192
PWM_CLOCK=4

CONFIG_FILE="/etc/opifancontrol.conf"

# Detect if gpio command is available
if ! command -v gpio > /dev/null; then
    echo "Error: gpio command not found. Please install wiringPi."
    echo "See: https://github.com/jamsinclair/opifancontrol?tab=readme-ov-file#software-installation"
    exit 1
fi

if [ -r "$CONFIG_FILE" ]; then
    source "$CONFIG_FILE"
else
    echo "Warning: Configuration file not found at /etc/opifancontrol.conf. Using default values."
fi

CURRENT_PWM=0
LAST_RAMPED_DOWN_TS=0

# Initialize GPIO pin for PWM
gpio mode $FAN_GPIO_PIN pwm
gpio pwm $FAN_GPIO_PIN 0
gpio pwmr $FAN_GPIO_PIN $PWM_RANGE
gpio pwmc $FAN_GPIO_PIN $PWM_CLOCK
# Need to set to 0 again after setting the clock and range
gpio pwm $FAN_GPIO_PIN 0

debug () {
    if [ "$DEBUG" = true ]; then
        echo "$1"
    fi
}

echo "Starting opifancontrol (v$OPIFANCONTROL_VERSION) ..."
echo "PWM range: $PWM_RANGE"
echo "PWM clock: $PWM_CLOCK"
echo "Fan GPIO pin: $FAN_GPIO_PIN"
echo "Temperature poll interval: $TEMP_POLL_SECONDS seconds"
echo "Temperature thresholds (C): $TEMP_LOW, $TEMP_MED, $TEMP_HIGH"
echo "Fan speed thresholds (%): $FAN_LOW, $FAN_MED, $FAN_HIGH"
echo "Ramp up delay: $RAMP_UP_DELAY_SECONDS seconds"
echo "Ramp down delay: $RAMP_DOWN_DELAY_SECONDS seconds"

percent_to_pwm() {
    local percent=$1
    if [ $percent -gt 100 ]; then
        percent=100
    fi
    local pwm=$((percent * PWM_RANGE / 100))
    printf "%.0f" $pwm
}

cleanup() {
    echo "Turning off the fan..."
    gpio pwm $FAN_GPIO_PIN 0
    exit 0
}

# Set trap to call cleanup function on script exit
trap cleanup EXIT

smooth_ramp() {
    local current_pwm=$1
    local target_pwm=$2
    local ramp_step=$3
    local ramp_delay=$4

    while [ $current_pwm -ne $target_pwm ]; do
        if [ $target_pwm -eq 0 ]; then
            current_pwm=0
        elif [ $current_pwm -eq 0 ]; then
            current_pwm=$target_pwm
        elif [ $current_pwm -lt $target_pwm ]; then
            current_pwm=$((current_pwm + ramp_step))
            if [ $current_pwm -gt $target_pwm ]; then
                current_pwm=$target_pwm
            fi
        else
            current_pwm=$((current_pwm - ramp_step))
            if [ $current_pwm -lt $target_pwm ]; then
                current_pwm=$target_pwm
            fi
        fi

        gpio pwm $FAN_GPIO_PIN $current_pwm

        sleep $ramp_delay
    done

    CURRENT_PWM=$target_pwm
}

while true; do
    CPU_TEMP=$(cat /sys/class/thermal/thermal_zone1/temp)
    CPU_TEMP=$((CPU_TEMP / 1000))

    if [ $CPU_TEMP -lt $TEMP_LOW ]; then
        TARGET_PWM=0
    elif [ $CPU_TEMP -lt $TEMP_MED ]; then
        TARGET_PWM=$(percent_to_pwm $FAN_LOW)
    elif [ $CPU_TEMP -lt $TEMP_HIGH ]; then
        TARGET_PWM=$(percent_to_pwm $FAN_MED)
    else
        TARGET_PWM=$(percent_to_pwm $FAN_HIGH)
    fi

    if [ $TARGET_PWM -ne $CURRENT_PWM ]; then
        BASE_RAMP_UP_DELAY_TS=$(date +%s)
        # If the fan is currently off, wait for the ramp up delay before turning it on to avoid rapid on/off cycles
        if [ $TARGET_PWM -gt $CURRENT_PWM ] && [ $((LAST_RAMPED_DOWN_TS + $RAMP_UP_DELAY_SECONDS)) -gt $BASE_RAMP_UP_DELAY_TS ]; then
            RAMP_UP_DELAY_REMAIN_SECONDS=$(($RAMP_UP_DELAY_SECONDS - $BASE_RAMP_UP_DELAY_TS + $LAST_RAMPED_DOWN_TS))
            debug "Delay of $RAMP_UP_DELAY_REMAIN_SECONDS sec before turning on the fan ... Target PWM: $TARGET_PWM"
            sleep $RAMP_UP_DELAY_REMAIN_SECONDS
        fi

        if [ $TARGET_PWM -eq 0 ] && [ $CURRENT_PWM -ne 0 ]; then
            # Wait for the ramp down delay before turning off the fan to avoid rapid on/off cycles
            debug "Delay of $RAMP_DOWN_DELAY_SECONDS sec before turning off the fan ... Target PWM: $TARGET_PWM"
            sleep $RAMP_DOWN_DELAY_SECONDS
            debug "Turning off the fan"
            LAST_RAMPED_DOWN_TS=$(date +%s)
        fi

        debug "Changing Fan Speed | CPU temp: $CPU_TEMP, target PWM: $TARGET_PWM, current PWM: $CURRENT_PWM"
        smooth_ramp $CURRENT_PWM $TARGET_PWM 2 0.2
    fi

    sleep $TEMP_POLL_SECONDS
done
