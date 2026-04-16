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
        { pkgs, ... }:
        {
          home.stateVersion = "24.11";
          virtualisation.quadlet = {
            enable = true;
            containers = {
              nginx = {
                containerConfig = {
                  Image = "docker-archive:${pkgs.dockerTools.examples.nginx}";
                  PublishPort = [ "8080:80" ];
                };
              };
              nginx-image-stream = {
                imageStream = pkgs.dockerTools.examples.nginxStream;
                containerConfig = {
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
      containers = nodes.machine.home-manager.users.quadlet.virtualisation.quadlet.containers;
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
    '';
}
