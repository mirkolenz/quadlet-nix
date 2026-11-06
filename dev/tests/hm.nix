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
      home-manager.users.quadlet =
        { pkgs, config, ... }:
        {
          home.stateVersion = "24.11";
          # The Podman of nixpkgs, as on other distributions, instead of the
          # wrapped one of NixOS.
          services.podman.package = pkgs.podman;
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

      def as_user(command):
          return f"sudo -H -u ${user.name} XDG_RUNTIME_DIR=/run/user/${toString user.uid} {command}"

      def expect_containers(count):
          running = len(json.loads(machine.succeed("sudo -u ${user.name} -- podman ps --format json")))
          assert running == count, f"Expected {count} containers, got: {running}"

      def serves(port):
          assert 'nginx' in machine.succeed(f"curl http://127.0.0.1:{port}").lower()

      machine.wait_for_unit("multi-user.target")
      machine.wait_for_unit("podman-user-wait-network-online.service", "${user.name}")

      machine.wait_for_unit("${containers.nginx.serviceName}.service", "${user.name}")
      serves(8080)
      expect_containers(2)

      machine.stop_job("${containers.nginx.serviceName}.service", "${user.name}")
      machine.fail("curl http://127.0.0.1:8080")
      expect_containers(1)

      machine.start_job("${containers.nginx.serviceName}.service", "${user.name}")
      serves(8080)
      expect_containers(2)

      machine.wait_for_unit("${containers.nginx-image-stream.serviceName}.service", "${user.name}")
      serves(8081)

      machine.succeed(as_user("${home.virtualisation.quadlet.quadletctl.package}/bin/quadletctl systemctl is-active ${containers.nginx.serviceName} --quiet"))

      # The auto-update timer runs its service at the configured schedule.
      timer = machine.get_unit_property("quadlet-update.timer", "TimersCalendar", "${user.name}")
      assert "Mon *-*-* 00:00:00" in timer, f"unexpected schedule: {timer}"
      timeout = machine.get_unit_property("quadlet-update.service", "TimeoutStartUSec", "${user.name}")
      assert timeout == "15min", f"unexpected timeout: {timeout}"
      machine.succeed(as_user("systemctl --user start quadlet-prune.service"))
    '';
}
