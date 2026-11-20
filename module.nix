self:
{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (lib)
    getExe
    mkEnableOption
    mkIf
    mkOption
    mkPackageOption
    optional
    optionalAttrs
    optionalString
    recursiveUpdate
    types
    ;

  cfg = config.services.radiance;
  yaml = pkgs.formats.yaml { };

  configFile = yaml.generate "radiance.yaml" (
    recursiveUpdate cfg.settings (
      optionalAttrs (cfg.apiKeyFile != null) { server.api-key-env = "RADIANCE_API_KEY"; }
    )
  );

  start = pkgs.writeShellScript "radiance-start" /* sh */ ''
    ${optionalString (cfg.apiKeyFile != null) /* sh */ ''
      RADIANCE_API_KEY=$(< "$CREDENTIALS_DIRECTORY/api-key")
      export RADIANCE_API_KEY
    ''}
    exec ${getExe cfg.package} --config ${configFile}
  '';
in
{
  options.services.radiance = {
    enable = mkEnableOption "the radiance inference server";

    package = mkPackageOption self.packages.${pkgs.stdenv.hostPlatform.system} "radiance" { };

    settings = mkOption {
      inherit (yaml) type;
      default = { };
      example = {
        server.port = 8080;
        models."qwen3.8-27b" = {
          model = "/var/lib/radiance/qwen3.8-27b-iq4r-l-v4.rad";
          tp = 2;
          max-num-seqs = 8;
          max-model-len = 262144;
          kv-cache-dtype = "i8";
          prefix-resume = "nearest";
        };
      };
      description = ''
        Contents of the YAML file passed to `radiance --config`. `radiance --help`
        lists every key.
      '';
    };

    apiKeyFile = mkOption {
      type = types.nullOr types.path;
      default = null;
      description = ''
        File holding the API key. When set, every request but the health probes
        must carry it as `Authorization: Bearer` or `X-Api-Key`.
      '';
    };

    openFirewall = mkEnableOption "opening the server port in the firewall";
  };

  config = mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.settings ? models && cfg.settings.models != { };
        message = "services.radiance.settings.models must name at least one model.";
      }
    ];

    systemd.services.radiance = {
      description = "radiance inference server";
      wantedBy = [ "multi-user.target" ];
      after = [ "network.target" ];

      serviceConfig = {
        ExecStart = start;
        LoadCredential = optional (cfg.apiKeyFile != null) "api-key:${cfg.apiKeyFile}";
        User = "radiance";
        Group = "radiance";
        SupplementaryGroups = [
          "render"
          "video"
        ];
        StateDirectory = "radiance";
        LimitMEMLOCK = "infinity";
        Restart = "on-failure";
        # On SIGTERM the server finishes the in-flight step and releases the cards.
        TimeoutStopSec = 60;
      };
    };

    users.users.radiance = {
      isSystemUser = true;
      group = "radiance";
    };
    users.groups.radiance = { };

    networking.firewall.allowedTCPPorts = mkIf cfg.openFirewall [
      (cfg.settings.server.port or 8000)
    ];
  };
}
