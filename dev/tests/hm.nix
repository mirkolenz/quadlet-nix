{ ... }:
{
  nodes.machine =
    { pkgs, lib, ... }:
    {
      systemd.services.hm-wait-network-online = {
        description = "Pull in network-online.target for rootless Home Manager podman tests";
        wantedBy = [ "multi-user.target" ];
        wants = [ "network-online.target" ];
        after = [ "network-online.target" ];
        serviceConfig = {
          Type = "oneshot";
          ExecStart = lib.getExe' pkgs.coreutils "true";
          RemainAfterExit = true;
        };
      };
      users.users.quadlet = {
        isSystemUser = true;
        uid = 990;
        linger = true;
        home = "/var/lib/quadlet";
        createHome = true;
        shell = pkgs.shadow;
        autoSubUidGidRange = true;
        group = "quadlet";
      };
      users.groups.quadlet = {
        gid = 990;
      };
      home-manager.users.quadlet =
        { pkgs, config, ... }:
        {
          home.stateVersion = "24.11";
          virtualisation.quadlet = {
            enable = true;
            autoUpdate = {
              enable = true;
              startAt = "weekly";
            };
            autoPrune.enable = true;
            images.nginx.package = pkgs.dockerTools.examples.nginxStream;
            containers = {
              nginx = {
                containerConfig = {
                  Image = "docker-archive:${pkgs.dockerTools.examples.nginx}";
                  PublishPort = [ "8080:80" ];
                };
              };
              nginx-image-stream = {
                containerConfig = {
                  Image = config.virtualisation.quadlet.images.nginx.ref;
                  PublishPort = [ "8081:80" ];
                };
              };
            };
          };
        };
    };
  testScript =
    { nodes }:
    let
      home = nodes.machine.home-manager.users.quadlet;
      containers = home.virtualisation.quadlet.containers;
      user = nodes.machine.users.users.quadlet;
    in
    ''
      import json

      machine.wait_for_unit("multi-user.target")
      machine.wait_for_unit("podman-user-wait-network-online.service", "${user.name}")

      machine.wait_for_unit("${containers.nginx.serviceName}.service", "${user.name}")
      assert 'nginx' in machine.succeed("curl http://127.0.0.1:8080").lower()
      containers = json.loads(machine.succeed("sudo -u ${user.name} -- podman ps --format json"))
      assert len(containers) == 2, f"Expected 2 user containers, got: {len(containers)}"

      machine.stop_job("${containers.nginx.serviceName}.service", "${user.name}")
      machine.fail("curl http://127.0.0.1:8080")
      containers = json.loads(machine.succeed("sudo -u ${user.name} -- podman ps --format json"))
      assert len(containers) == 1, f"Expected 1 user container, got: {len(containers)}"

      machine.start_job("${containers.nginx.serviceName}.service", "${user.name}")
      assert 'nginx' in machine.succeed("curl http://127.0.0.1:8080").lower()
      containers = json.loads(machine.succeed("sudo -u ${user.name} -- podman ps --format json"))
      assert len(containers) == 2, f"Expected 2 user containers, got: {len(containers)}"

      machine.wait_for_unit("${containers.nginx-image-stream.serviceName}.service", "${user.name}")
      assert 'nginx' in machine.succeed("curl http://127.0.0.1:8081").lower()

      machine.succeed("sudo -H -u ${user.name} XDG_RUNTIME_DIR=/run/user/${toString user.uid} ${home.virtualisation.quadlet.quadletctl.package}/bin/quadletctl systemctl is-active ${containers.nginx.serviceName} --quiet")

      # The auto-update timer, at the configured schedule, runs Podman's own service.
      timer = machine.get_unit_property("quadlet-auto-update.timer", "TimersCalendar", "${user.name}")
      assert "Mon *-*-* 00:00:00" in timer, f"unexpected schedule: {timer}"
      timeout = machine.get_unit_property("podman-auto-update.service", "TimeoutStartUSec", "${user.name}")
      assert timeout == "15min", f"unexpected timeout: {timeout}"
      machine.succeed("sudo -H -u ${user.name} XDG_RUNTIME_DIR=/run/user/${toString user.uid} systemctl --user start quadlet-image-prune.service")
    '';
}
