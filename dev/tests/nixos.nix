{ ... }:
{
  nodes.machine =
    { pkgs, config, ... }:
    {
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
      # A previous build of the Nix-built image, which no container uses.
      environment.etc."previous.tar".source = pkgs.dockerTools.buildImage {
        name = "previous";
        tag = "previous";
      };
      virtualisation.quadlet = {
        autoUpdate.enable = true;
        autoPrune.enable = true;
        images.nginx.package = pkgs.dockerTools.examples.nginxStream;
        containers = {
          nginx-shared.containerConfig = {
            Image = config.virtualisation.quadlet.images.nginx.ref;
            PublishPort = [ "8086:80" ];
          };
          nginx = {
            containerConfig = {
              Image = "docker-archive:${pkgs.dockerTools.examples.nginx}";
              PublishPort = [ "8080:80" ];
              Environment = {
                TZ = "Europe/Berlin";
              };
            };
          };
          # Loads the same build as the image unit, concurrently.
          nginx-image-stream = {
            imagePackage = pkgs.dockerTools.examples.nginxStream;
            containerConfig.PublishPort = [ "8081:80" ];
          };
          # Loads a Nix-built image into rootless storage.
          nginx-rootless = {
            uid = config.users.users.quadlet.uid;
            imagePackage = pkgs.dockerTools.examples.nginxStream;
            containerConfig.PublishPort = [ "8082:80" ];
          };
        };
      };
    };
  testScript =
    { nodes }:
    let
      containers = nodes.machine.virtualisation.quadlet.containers;
      images = nodes.machine.virtualisation.quadlet.images;
      user = nodes.machine.users.users.quadlet;
    in
    ''
      import json
      import re

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

      def expect_containers(count, podman="podman"):
          running = len(json.loads(machine.succeed(f"{podman} ps --format json")))
          assert running == count, f"Expected {count} containers, got: {running}"

      def serves(port):
          assert 'nginx' in machine.succeed(f"curl http://127.0.0.1:{port}").lower()

      machine.wait_for_unit("multi-user.target")

      machine.wait_for_unit("${containers.nginx.serviceName}.service")
      machine.wait_for_unit("${containers.nginx-shared.serviceName}.service")
      serves(8080)
      expect_containers(3)

      machine.stop_job("${containers.nginx.serviceName}.service")
      machine.fail("curl http://127.0.0.1:8080")
      expect_containers(2)

      machine.start_job("${containers.nginx.serviceName}.service")
      serves(8080)
      expect_containers(3)

      machine.wait_for_unit("${containers.nginx-image-stream.serviceName}.service")
      serves(8081)

      machine.wait_for_unit("${containers.nginx-rootless.serviceName}.service", "${user.name}")
      expect_containers(1, "quadletctl podman ${containers.nginx-rootless.serviceName}")
      serves(8082)
      # Only the reference names a loaded image, not the name stored in its archive.
      machine.succeed("quadletctl podman ${containers.nginx-rootless.serviceName} image exists ${containers.nginx-rootless.containerConfig.Image}")
      machine.fail("quadletctl podman ${containers.nginx-rootless.serviceName} image exists ${containers.nginx-rootless.imagePackage.imageName}:${containers.nginx-rootless.imagePackage.imageTag}")

      # quadletctl dispatches every unit to the manager, journal and podman storage of its owner.
      units = machine.succeed("quadletctl list")
      for service, podman in [("${containers.nginx.serviceName}", "${containers.nginx.podmanName}"), ("${containers.nginx-rootless.serviceName}", "${containers.nginx-rootless.podmanName}")]:
          machine.succeed(f"quadletctl systemctl is-active {service} --quiet")
          machine.succeed(f"quadletctl podman {service} exec {podman} nginx -v")
          assert re.search(rf"^{service} .* {podman} +active$", units, re.MULTILINE), units
      machine.fail("quadletctl podman ${containers.nginx-rootless.serviceName} exec ${containers.nginx-rootless.podmanName} false")
      machine.wait_until_succeeds("quadletctl journalctl ${containers.nginx-rootless.serviceName} --no-pager | grep -q 'GET /'")

      # The image unit and `nginx-image-stream` load the same build concurrently
      # at boot, so either of them may have done it.
      def loads():
          return machine.succeed("journalctl -u ${images.nginx.serviceName}.service | grep -c 'Writing manifest'").strip()

      serves(8086)
      booted = loads()

      # A restarted image unit skips the load while the build is present.
      machine.succeed("systemctl restart ${images.nginx.serviceName}.service")
      machine.wait_for_unit("${containers.nginx-shared.serviceName}.service")
      assert loads() == booted, f"unexpected number of loads: {loads()}"

      # Pruning removes the images that no container uses, such as a previous
      # build, and the image of stopped units, which their next start loads
      # again. The `nginx` container runs the same image from its archive.
      machine.succeed("podman load -i /etc/previous.tar")
      machine.succeed("systemctl is-active quadlet-prune.timer")
      machine.succeed("systemctl start quadlet-prune.service")
      machine.fail("podman image exists localhost/previous:previous")
      machine.succeed("podman image exists ${images.nginx.podmanName}")
      nginx_services = ["${containers.nginx-shared.serviceName}.service", "${containers.nginx-image-stream.serviceName}.service", "${containers.nginx.serviceName}.service"]
      for service in nginx_services:
          machine.stop_job(service)
      machine.succeed("systemctl start quadlet-prune.service")
      machine.fail("podman image exists ${images.nginx.podmanName}")
      for service in nginx_services:
          machine.start_job(service)
      serves(8086)
      serves(8081)

      running = snapshot()

      machine.succeed("${nodes.machine.system.build.toplevel}/specialisation/one/bin/switch-to-configuration test")
      machine.wait_for_unit("default.target", "${user.name}")
      serves(8085)
      expect_containers(4)
      running = check_untouched(running, "Adding a container")

      machine.succeed("${nodes.machine.system.build.toplevel}/bin/switch-to-configuration test")
      machine.wait_for_unit("default.target", "${user.name}")
      machine.fail("curl http://127.0.0.1:8085")
      expect_containers(3)
      running = check_untouched(running, "Removing a container")

      reload_env_check = "quadletctl podman ${containers.nginx-rootless.serviceName} inspect ${containers.nginx-rootless.podmanName} --format '{{range .Config.Env}}{{println .}}{{end}}' | grep -qx QUADLET_RELOAD_TEST=reloaded"
      machine.fail(reload_env_check)
      machine.succeed("${nodes.machine.system.build.toplevel}/specialisation/userReload/bin/switch-to-configuration test")
      machine.wait_for_unit("default.target", "${user.name}")
      machine.wait_until_succeeds(reload_env_check)
      check_untouched(running, "Changing one container", skip="${containers.nginx-rootless.serviceName}.service")
    '';
}
