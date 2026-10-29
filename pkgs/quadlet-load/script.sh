reference=$1
image=$2

if skopeo inspect --raw "containers-storage:$reference" >/dev/null 2>&1; then
  exit
fi

# The image comes from the Nix store, so no signature policy applies.
copy() {
  skopeo --insecure-policy copy docker-archive:/dev/stdin "containers-storage:$reference"
}

# A stream is an executable writing the image to stdout, unlike an archive.
if [[ -x $image ]]; then
  "$image" | copy
else
  copy <"$image"
fi
