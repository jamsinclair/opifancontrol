# Changelog

## 1.1.0
- Changes the default PWM range from 192 to 96
- Changes the default PWM clock from 4 to 10
- Adds a minimum fan speed percentage (default 30%) to ensure fans always spin when on
    - Can be adjusted with the `FAN_MIN_PERCENT` variable.
- Updates the ramping logic to the PWM range steps for smoother transitions.
    - Default ramp percent per step is 2% with a delay of 0.03 seconds between steps
    - Can be adjusted with the `RAMP_PERCENT_PER_STEP` and `RAMP_STEP_DELAY` variables.

## 1.0.2
- Updates startup logging to include if debugging is enabled or not
- Updates the README.md to include a section on debugging
