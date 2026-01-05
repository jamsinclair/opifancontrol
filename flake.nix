{
  description = "Orange Pi Fan Control with wiringOP - Multi-Fan Support";

  inputs = {
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = {
    self,
    nixpkgs,
    flake-utils,
  }:
    flake-utils.lib.eachDefaultSystem (
      system: let
        pkgs = nixpkgs.legacyPackages.${system};

        # wiringOP package definition
        wiringOP = let
          version = "unstable-2023-11-16";
          srcAll = pkgs.fetchFromGitHub {
            owner = "orangepi-xunlong";
            repo = "wiringOP";
            rev = "8cb35ff967291aca24f22af151aaa975246cf861";
            sha256 = "sha256-W6lZh4nEhhpkdcu/PWbVmjcvfhu6eqRGlkj8jiphG+k=";
          };
          mkSubProject = {
            subprj, # The only mandatory argument
            buildInputs ? [],
            src ? srcAll,
          }:
            pkgs.stdenv.mkDerivation (finalAttrs: {
              pname = "wiringop-${subprj}";
              inherit version src;
              sourceRoot = "${src.name}/${subprj}";
              inherit buildInputs;
              # Remove (meant for other OSs) lines from Makefiles
              preInstall = ''
                mkdir -p $out/bin
                sed -i "/chown root/d" Makefile
                sed -i "/chmod/d" Makefile
                sed -i "/ldconfig/d" Makefile
              '';
              makeFlags = [
                "DESTDIR=${placeholder "out"}"
                "PREFIX=/."
                # On NixOS we don't need to run ldconfig during build:
                "LDCONFIG=echo"
              ];
            });
          passthru = {
            # Helps nix-update and probably nixpkgs-update find the src of this package
            # automatically.
            src = srcAll;
            inherit mkSubProject;
            wiringPi = mkSubProject {
              subprj = "wiringPi";
              buildInputs = [pkgs.libxcrypt];
            };
            devLib = mkSubProject {
              subprj = "devLib";
              buildInputs = [passthru.wiringPi];
            };
            gpio = mkSubProject {
              subprj = "gpio";
              buildInputs = [
                pkgs.libxcrypt
                passthru.wiringPi
                passthru.devLib
              ];
            };
          };
        in
          pkgs.symlinkJoin {
            name = "wiringop-${version}";
            inherit passthru;
            paths = [
              passthru.wiringPi
              passthru.devLib
              passthru.gpio
            ];
            meta = with pkgs.lib; {
              description = "GPIO access library for Orange Pi (wiringPi port)";
              homepage = "https://github.com/orangepi-xunlong/wiringOP";
              license = licenses.lgpl3Plus;
              maintainers = [];
              platforms = platforms.linux;
            };
          };

        # opifancontrol package definition
        opifancontrol = pkgs.stdenv.mkDerivation rec {
          pname = "opifancontrol";
          version = "1.0.2";

          src = pkgs.writeTextFile {
            name = "opifancontrol-script";
            text = builtins.readFile ./opifancontrol.sh;
            executable = true;
          };

          dontUnpack = true;
          dontBuild = true;

          installPhase = ''
            mkdir -p $out/bin
            cp $src $out/bin/opifancontrol
          '';

          meta = with pkgs.lib; {
            description = "Fan control script for Orange Pi boards";
            homepage = "https://github.com/jamsinclair/opifancontrol";
            license = licenses.mit;
            maintainers = [];
            platforms = platforms.linux;
          };
        };
      in {
        packages = {
          inherit wiringOP opifancontrol;
          default = opifancontrol;
        };

        # For development, get wiringOP "gpio" binary.
        devShells.default = pkgs.mkShell {
          buildInputs = [wiringOP opifancontrol];
        };
      }
    )
    // {
      # NixOS module
      nixosModules.default = {
        config,
        lib,
        pkgs,
        ...
      }: let
        cfg = config.services.opifancontrol;

        # Define the fan configuration type
        fanConfigType = lib.types.submodule {
          options = {
            fanGpioPin = lib.mkOption {
              type = lib.types.int;
              default = 6;
              description = "The GPIO pin to use for the fan (wPi pin number)";
            };

            tempLow = lib.mkOption {
              type = lib.types.int;
              default = 55;
              description = "Low temperature threshold in Celsius";
            };

            fanLow = lib.mkOption {
              type = lib.types.int;
              default = 50;
              description = "Fan speed percentage for low temperature";
            };

            tempMed = lib.mkOption {
              type = lib.types.int;
              default = 65;
              description = "Medium temperature threshold in Celsius";
            };

            fanMed = lib.mkOption {
              type = lib.types.int;
              default = 75;
              description = "Fan speed percentage for medium temperature";
            };

            tempHigh = lib.mkOption {
              type = lib.types.int;
              default = 70;
              description = "High temperature threshold in Celsius";
            };

            fanHigh = lib.mkOption {
              type = lib.types.int;
              default = 100;
              description = "Fan speed percentage for high temperature";
            };

            tempPollSeconds = lib.mkOption {
              type = lib.types.int;
              default = 2;
              description = "Temperature polling interval in seconds";
            };

            rampUpDelaySeconds = lib.mkOption {
              type = lib.types.int;
              default = 15;
              description = "Delay before turning fan on to avoid rapid on/off cycles";
            };

            rampDownDelaySeconds = lib.mkOption {
              type = lib.types.int;
              default = 60;
              description = "Delay before turning fan off to avoid rapid on/off cycles";
            };

            rampPercentPerStep = lib.mkOption {
              type = lib.types.int;
              default = 2;
              description = "Percentage to change fan speed per step when ramping";
            };

            rampStepDelay = lib.mkOption {
              type = lib.types.float;
              default = 0.03;
              description = "Delay in seconds between each ramping step";
            };

            fanMinPercent = lib.mkOption {
              type = lib.types.int;
              default = 30;
              description = "Minimum fan speed percentage when the fan is on";
            };

            pwmRange = lib.mkOption {
              type = lib.types.int;
              default = 96;
              description = "PWM range for fan control";
            };

            pwmClock = lib.mkOption {
              type = lib.types.int;
              default = 10;
              description = "PWM clock for fan control";
            };

            debug = lib.mkOption {
              type = lib.types.bool;
              default = false;
              description = "Enable debug logging";
            };
          };
        };

        # Generate configuration file content for a specific fan
        mkConfigFile = fanName: fanConfig:
          pkgs.writeText "opifancontrol-${fanName}.conf" ''
            FAN_GPIO_PIN=${toString fanConfig.fanGpioPin}
            TEMP_LOW=${toString fanConfig.tempLow}
            FAN_LOW=${toString fanConfig.fanLow}
            TEMP_MED=${toString fanConfig.tempMed}
            FAN_MED=${toString fanConfig.fanMed}
            TEMP_HIGH=${toString fanConfig.tempHigh}
            FAN_HIGH=${toString fanConfig.fanHigh}
            TEMP_POLL_SECONDS=${toString fanConfig.tempPollSeconds}
            RAMP_UP_DELAY_SECONDS=${toString fanConfig.rampUpDelaySeconds}
            RAMP_DOWN_DELAY_SECONDS=${toString fanConfig.rampDownDelaySeconds}
            RAMP_PERCENT_PER_STEP=${toString fanConfig.rampPercentPerStep}
            RAMP_STEP_DELAY=${toString fanConfig.rampStepDelay}
            FAN_MIN_PERCENT=${toString fanConfig.fanMinPercent}
            PWM_RANGE=${toString fanConfig.pwmRange}
            PWM_CLOCK=${toString fanConfig.pwmClock}
            DEBUG=${
              if fanConfig.debug
              then "true"
              else "false"
            }
          '';

        # Create systemd service for a specific fan
        mkFanService = fanName: fanConfig: let
          configFile = mkConfigFile fanName fanConfig;
        in {
          "opifancontrol-${fanName}" = {
            description = "Orange Pi Fan Control Service - ${fanName}";
            wantedBy = ["multi-user.target"];
            after = ["multi-user.target"];

            serviceConfig = {
              Type = "simple";
              ExecStart = "${cfg.package}/bin/opifancontrol ${configFile}";
              Restart = "on-failure";
              User = "root"; # GPIO access typically requires root
              # Ensure the service can find system binaries
              Environment = "PATH=${pkgs.lib.makeBinPath [cfg.wiringOP pkgs.coreutils pkgs.bash]}";
            };

            # Only start if the thermal zone file exists (i.e., on Orange Pi)
            unitConfig = {
              ConditionPathExists = "/sys/class/thermal/thermal_zone1/temp";
            };

            # Restart service when configuration changes
            restartTriggers = [configFile];
          };
        };

        # Generate all fan services
        fanServices = lib.mkMerge (lib.mapAttrsToList mkFanService cfg.fans);
      in {
        options.services.opifancontrol = {
          enable = lib.mkEnableOption "Orange Pi Fan Control Service";

          package = lib.mkOption {
            type = lib.types.package;
            default = self.packages.${pkgs.system}.opifancontrol;
            description = "The opifancontrol package to use";
          };

          wiringOP = lib.mkOption {
            type = lib.types.package;
            default = self.packages.${pkgs.system}.wiringOP;
            description = "The wiringOP package to use";
          };

          fans = lib.mkOption {
            type = lib.types.attrsOf fanConfigType;
            default = {};
            description = "Configuration for each fan";
            example = lib.literalExpression ''
              {
                cpu = {
                  fanGpioPin = 6;
                  tempLow = 45;
                  fanLow = 30;
                  tempMed = 55;
                  fanMed = 60;
                  tempHigh = 65;
                  fanHigh = 100;
                  debug = true;
                };
                closet = {
                  fanGpioPin = 22;
                  tempLow = 45;
                  fanLow = 30;
                  tempMed = 55;
                  fanMed = 60;
                  tempHigh = 65;
                  fanHigh = 100;
                  debug = true;
                };
              }
            '';
          };

          boardType = lib.mkOption {
            type = lib.types.str;
            default = "orangepi5plus";
            description = "Orange Pi board type";
          };
        };

        config = lib.mkIf cfg.enable {
          # Set up the board identification file or gpio refuses to work
          environment.etc."orangepi-release".text = "BOARD=${cfg.boardType}";

          # Define the systemd services for all fans
          systemd.services = fanServices;
        };
      };
    };
}
