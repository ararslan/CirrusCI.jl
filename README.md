# CirrusCI.jl

This repository contains utilities for using Julia on [Cirrus CI](https://cirrus-ci.org).
Note that while Cirrus supports multiple systems, currently this script only supports FreeBSD
builds.
For the time being, users are encouraged to continue to use Travis CI for Linux and macOS
and AppVeyor for Windows.
Support for those systems may be revisited here in the future.

This is still in an alpha stage; there may be future changes.

## Usage

Create a file called `.cirrus.yml` in the root directory of your Julia project and populate
it with the following template:

```yaml
freebsd_instance:
  image: freebsd-12-0-release-amd64
task:
  name: FreeBSD
  env:
    matrix:
      - JULIA_VERSION: 1.0
      - JULIA_VERSION: 1.1
  install_script:
    - sh -c "$(fetch https://raw.githubusercontent.com/ararslan/CirrusCI.jl/master/bin/install.sh -o -)"
  build_script:
    - julia --color=yes "using Pkg; Pkg.add(PackageSpec(name=\"YourPackage\", path=pwd()))"
    - julia --color=yes "using Pkg; Pkg.build(\"YourPackage\")"
  test_script:
    - julia --color=yes "using Pkg; Pkg.test(\"YourPackage\")"
```

## Still to do

* Improve consistency for packages with and without Project.toml files
* Provide conveniences for coverage submission
