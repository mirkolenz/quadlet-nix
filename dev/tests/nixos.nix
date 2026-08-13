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
      specialisation.one.configuration = {
        virtualisation.quadlet.containers.nginx-specialized = {
          containerConfig = {
            Image = "docker-archive:${pkgs.dockerTools.examples.nginx}";
            PublishPort = [ "8085:80" ];
          };
        };
      };
      specialisation.userReload.configuration = {
        virtualisation.quadlet.containers.nginx-rootless.containerConfig.Environment = {
          QUADLET_RELOAD_TEST = "reloaded";
        };
      };
      virtualisation.quadlet = {
        containers = {
          nginx = {
            containerConfig = {
              Image = "docker-archive:${pkgs.dockerTools.examples.nginx}";
              PublishPort = [ "8080:80" ];
              Environment = {
                TZ = "Europe/Berlin";
              };
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

      # A restart gives a unit a fresh invocation id.
      tracked = {
        "${containers.nginx.serviceName}.service": None,
        "${containers.nginx-image-stream.serviceName}.service": None,
        "${containers.nginx-rootless.serviceName}.service": "${user.name}",
      }

      def snapshot():
          return {u: machine.get_unit_property(u, "InvocationID", user) for u, user in tracked.items()}

      def check_untouched(before, message, skip=None):
          after = snapshot()
          for unit in before:
              if unit != skip:
                  assert after[unit] == before[unit], f"{message}: {unit} was restarted"
          return after

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

      running = snapshot()

      machine.succeed("${nodes.machine.system.build.toplevel}/specialisation/one/bin/switch-to-configuration test")
      machine.wait_for_unit("default.target", "${user.name}")
      assert 'nginx' in machine.succeed("curl http://127.0.0.1:8085").lower()
      containers = json.loads(machine.succeed("podman ps --format json"))
      assert len(containers) == 3, f"Expected 3 system containers, got: {len(containers)}"
      running = check_untouched(running, "Adding a container")

      machine.succeed("${nodes.machine.system.build.toplevel}/bin/switch-to-configuration test")
      machine.wait_for_unit("default.target", "${user.name}")
      machine.fail("curl http://127.0.0.1:8083")
      containers = json.loads(machine.succeed("podman ps --format json"))
      assert len(containers) == 2, f"Expected 2 system containers, got: {len(containers)}"
      running = check_untouched(running, "Removing a container")

      reload_env_check = "sudo -u ${user.name} -- podman inspect ${containers.nginx-rootless.podmanName} --format '{{range .Config.Env}}{{println .}}{{end}}' | grep -qx QUADLET_RELOAD_TEST=reloaded"
      machine.fail(reload_env_check)
      machine.succeed("${nodes.machine.system.build.toplevel}/specialisation/userReload/bin/switch-to-configuration test")
      machine.wait_for_unit("default.target", "${user.name}")
      machine.wait_until_succeeds(reload_env_check)
      check_untouched(running, "Changing one container", skip="${containers.nginx-rootless.serviceName}.service")
    '';
}
