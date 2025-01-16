{ ... }:
{
  nodes.machine =
    { pkgs, config, ... }:
    {
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
      virtualisation.quadlet = {
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
          nginx-rootless = {
            uid = config.users.users.quadlet.uid;
            containerConfig = {
              Image = "docker-archive:${pkgs.dockerTools.examples.nginx}";
              PublishPort = [ "8082:80" ];
            };
          };
        };
      };
    };
  testScript =
    { nodes }:
    let
      containers = nodes.machine.virtualisation.quadlet.containers;
      user = nodes.machine.users.users.quadlet;
    in
    ''
      import json

      machine.wait_for_unit("multi-user.target")

      machine.wait_for_unit("${containers.nginx.serviceName}.service")
      assert 'nginx' in machine.succeed("curl http://127.0.0.1:8080").lower()
      containers = json.loads(machine.succeed("podman ps --format json"))
      assert len(containers) == 2, f"Expected 2 system containers, got: {len(containers)}"

      machine.stop_job("${containers.nginx.serviceName}.service")
      machine.fail("curl http://127.0.0.1:8080")
      containers = json.loads(machine.succeed("podman ps --format json"))
      assert len(containers) == 1, f"Expected 1 system container, got: {len(containers)}"

      machine.start_job("${containers.nginx.serviceName}.service")
      assert 'nginx' in machine.succeed("curl http://127.0.0.1:8080").lower()
      containers = json.loads(machine.succeed("podman ps --format json"))
      assert len(containers) == 2, f"Expected 2 system containers, got: {len(containers)}"

      machine.wait_for_unit("${containers.nginx-image-stream.serviceName}.service")
      assert 'nginx' in machine.succeed("curl http://127.0.0.1:8081").lower()

      machine.wait_for_unit("${containers.nginx-rootless.serviceName}.service", "${user.name}")
      containers = json.loads(machine.succeed("sudo -u ${user.name} -- podman ps --format json"))
      assert len(containers) == 1, f"Expected 1 user container, got: {len(containers)}"
      assert 'nginx' in machine.succeed("curl http://127.0.0.1:8082").lower()
    '';
}
