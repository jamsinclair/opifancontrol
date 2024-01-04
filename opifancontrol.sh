#!/bin/bash

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

if [ -r "$CONFIG_FILE" ]; then
    source "$CONFIG_FILE"
else
    echo "Warning: Configuration file not found at /etc/opifancontrol.conf. Using default values."
fi

CURRENT_PWM=0
LAST_RAMPED_DOWN_TS=0

# Initialize GPIO pin for PWM
gpio export $FAN_GPIO_PIN out
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

echo "Starting opifancontrol..."
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
    CPU_TEMP=$(cat /sys/class/thermal/thermal_zone0/temp)
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
        # If the fan is currently off, wait for the ramp up delay before turning it on to avoid rapid on/off cycles
        if [ $TARGET_PWM -gt $CURRENT_PWM ] && [ $((LAST_RAMPED_DOWN_TS + $RAMP_UP_DELAY_SECONDS)) -gt $(date +%s) ]; then
            TARGET_PWM=$CURRENT_PWM
        fi

        if [ $TARGET_PWM -eq 0 ]; then
            # Wait for the ramp down delay before turning off the fan to avoid rapid on/off cycles
            sleep $RAMP_DOWN_DELAY_SECONDS
            LAST_RAMPED_DOWN_TS=$(date +%s)
        fi

        debug "Changing Fan Speed | CPU temp: $CPU_TEMP, target PWM: $TARGET_PWM, current PWM: $CURRENT_PWM"
        smooth_ramp $CURRENT_PWM $TARGET_PWM 10 0.1
    fi

    sleep $TEMP_POLL_SECONDS
done
