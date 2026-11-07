# sa-core checksums

One file per release, `v<version>.txt`, in `sha256sum` format: the sha256 of each `sa-core-<target>`
binary attached to that GitHub release. `scripts/sa-native.sh` downloads the binary for the plugin's
version and refuses to run it unless it matches the line here. The release workflow refuses to publish
a release whose binaries do not match this file.

Written by the maintainer from the draft release that `.github/workflows/build-core.yml` creates;
see "Development" in the README.
