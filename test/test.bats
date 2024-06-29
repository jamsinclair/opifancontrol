#!/usr/bin/env bats

load './helpers.bash'

setup() {
    # Create a temporary directory for test configuration files
    export TEST_DIR=$(mktemp -d)
    export SCRIPT_LOG="$TEST_DIR/script.log"
    export CONFIG_FILE="./test/opifancontrol.conf"
    export DEBUG=true
    touch "$SCRIPT_LOG"

    # Create a mock gpio command
    export PATH="$TEST_DIR:$PATH"
    cat << 'EOF' > "$TEST_DIR/gpio"
#!/bin/bash
echo "$@" >> "$TEST_DIR/gpio.log"
EOF
    chmod +x "$TEST_DIR/gpio"

    # Create a mock temperature file
    export TEMP_FILE="$TEST_DIR/thermal_zone1/temp"
    mkdir -p "$(dirname "$TEMP_FILE")"
    echo "60000" > "$TEMP_FILE";

    # Override the path to the temperature file in the script
    sed_cross_platform "/sys/class/thermal/thermal_zone1/temp" "$TEMP_FILE" opifancontrol.sh
    # Override the path to the config file in the script
    sed_cross_platform "/etc/opifancontrol.conf" "$CONFIG_FILE" opifancontrol.sh
}

teardown() {
    rm -rf "$TEST_DIR"
    sed_cross_platform "$TEMP_FILE" "/sys/class/thermal/thermal_zone1/temp" opifancontrol.sh
    sed_cross_platform "$CONFIG_FILE" "/etc/opifancontrol.conf" opifancontrol.sh
}

@test "Fan should turn on at low speed when temperature is between TEMP_LOW and TEMP_MED" {
    echo "55000" > "$TEMP_FILE";
    ./opifancontrol.sh > $SCRIPT_LOG & sleep 2;
    pkill -f "opifancontrol.sh";

    EXPECTED_TARGET_PWM=$(percent_to_pwm 50)
    EXPECTED_CURRENT_PWM=0

    cat $SCRIPT_LOG # This will print the logs on failure
    cat $SCRIPT_LOG | grep "Changing Fan Speed | CPU temp: 55, target PWM: $EXPECTED_TARGET_PWM, current PWM: $EXPECTED_CURRENT_PWM"
}

@test "Fan should turn on at medium speed when temperature is between TEMP_MED and TEMP_HIGH" {
    echo "65000" > "$TEMP_FILE";
    ./opifancontrol.sh > $SCRIPT_LOG & sleep 2;
    pkill -f "opifancontrol.sh";

    EXPECTED_TARGET_PWM=$(percent_to_pwm 75)
    EXPECTED_CURRENT_PWM=0

    cat $SCRIPT_LOG # This will print the logs on failure
    cat $SCRIPT_LOG | grep "Changing Fan Speed | CPU temp: 65, target PWM: $EXPECTED_TARGET_PWM, current PWM: $EXPECTED_CURRENT_PWM"
}

@test "Fan should turn on at high speed when temperature is above TEMP_HIGH" {
    echo "70000" > "$TEMP_FILE";
    ./opifancontrol.sh > $SCRIPT_LOG & sleep 2;
    pkill -f "opifancontrol.sh";

    EXPECTED_TARGET_PWM=$(percent_to_pwm 100)
    EXPECTED_CURRENT_PWM=0

    cat $SCRIPT_LOG # This will print the logs on failure
    cat $SCRIPT_LOG | grep "Changing Fan Speed | CPU temp: 70, target PWM: $EXPECTED_TARGET_PWM, current PWM: $EXPECTED_CURRENT_PWM"
}

@test "Fan should wait for the ramp down duration before turning off" {
    echo "55000" > "$TEMP_FILE";
    ./opifancontrol.sh > $SCRIPT_LOG & sleep 2;
    echo "45000" > "$TEMP_FILE";
    sleep 2;
    if cat $SCRIPT_LOG | grep "Turning off the fan"; then 
        echo "Turning off the fan message should not be printed yet";
        pkill -f "opifancontrol.sh";
        exit 1;
    fi
    sleep 2;
    pkill -f "opifancontrol.sh";
    # Check that the turning off the fan message is printed
    cat $SCRIPT_LOG | grep "Turning off the fan"

    EXPECTED_TARGET_PWM=0
    EXPECTED_CURRENT_PWM=$(percent_to_pwm 50)

    cat $SCRIPT_LOG # This will print the logs on failure
    cat $SCRIPT_LOG | grep "Changing Fan Speed | CPU temp: 45, target PWM: $EXPECTED_TARGET_PWM, current PWM: $EXPECTED_CURRENT_PWM"
}

@test "Fan should wait for the ramp up duration before turning on again" {
    echo "55000" > "$TEMP_FILE";
    ./opifancontrol.sh > $SCRIPT_LOG & sleep 2;
    echo "45000" > "$TEMP_FILE";
    sleep 4;
    # Check that the turning off the fan message is printed
    if cat $SCRIPT_LOG | grep "Turning off the fan"; then 
        # noop
        echo "";
    else
        echo "Turning off the fan message should be printed";
        pkill -f "opifancontrol.sh";
        exit 1;
    fi
    echo "55000" > "$TEMP_FILE";
    sleep 2;

    EXPECTED_CURRENT_PWM=0
    EXPECTED_TARGET_PWM=$(percent_to_pwm 50)
    if cat $SCRIPT_LOG | grep "sec before turning on the fan ... Target PWM: $EXPECTED_TARGET_PWM"; then 
        # noop
        echo "";
    else
        cat $SCRIPT_LOG
        echo "Delay turn on fan message should be printed"
        pkill -f "opifancontrol.sh";
        exit 1
    fi
    sleep 2;
    pkill -f "opifancontrol.sh";

    tail -2 $SCRIPT_LOG # This will print the logs on failure
    tail -2 $SCRIPT_LOG | grep "Changing Fan Speed | CPU temp: 55, target PWM: $EXPECTED_TARGET_PWM, current PWM: $EXPECTED_CURRENT_PWM"
}
