#!/bin/bash

PWM_RANGE=192

percent_to_pwm() {
    local percent=$1
    if [ $percent -gt 100 ]; then
        percent=100
    fi
    local pwm=$((percent * PWM_RANGE / 100))
    printf "%.0f" $pwm
}

sed_cross_platform() {
    local pattern=$1
    local replacement=$2
    local file=$3

    if [ "$(uname)" == "Darwin" ]; then
        sed -i '' -e "s|$pattern|$replacement|" "$file"
    else
        sed -i "s|$pattern|$replacement|" "$file"
    fi
}
