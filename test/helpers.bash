#!/bin/bash

PWM_RANGE=96

percent_to_pwm() {
    local percent=$1
    if [ $percent -gt 100 ]; then percent=100; fi
    if [ $percent -lt 0 ]; then percent=0; fi
    echo $(((percent * PWM_RANGE + 50) / 100))
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
