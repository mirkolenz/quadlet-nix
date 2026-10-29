reference=$1
image=$2
name=$3
# The remaining arguments are the global arguments of the unit, such as `--root`.
shift 3

if podman "$@" image exists "$reference"; then
  exit
fi

# A stream is an executable writing the image to stdout, unlike an archive.
# The pull prints its progress to stderr and the image ID to stdout.
if [[ -x $image ]]; then
  id=$("$image" | podman "$@" pull docker-archive:/dev/stdin)
else
  id=$(podman "$@" pull "docker-archive:$image")
fi

# Tagging the ID stays correct while another build claims a fixed tag of the archive.
podman "$@" tag "$id" "$reference"

# Only the reference names the image, but the archive name may already belong
# to another build, so removing it must not fail the load.
podman "$@" untag "$id" "$name" || true
