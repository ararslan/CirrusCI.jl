# CirrusCI.jl

[![Cirrus](https://api.cirrus-ci.com/github/ararslan/CirrusCI.jl.svg)](https://cirrus-ci.com/github/ararslan/CirrusCI.jl)

This repository contains utilities for using Julia on [Cirrus CI](https://cirrus-ci.org).
Note that while Cirrus supports multiple systems, currently this script only supports FreeBSD
builds.
For the time being, users are encouraged to continue to use
[GitHub Actions](https://github.com/julia-actions/setup-julia) for Linux, macOS, and/or Windows builds.
Support for those systems may be revisited here in the future.

## Usage

Create a file called `.cirrus.yml` in the root directory of your Julia project and populate
it with the following template, modifying as you see fit:

```yaml
freebsd_instance:
  image: freebsd-13-0-release-amd64
task:
  name: FreeBSD
  env:
    matrix:
      - JULIA_VERSION: 1.6
      - JULIA_VERSION: 1
      - JULIA_VERSION: nightly
  allow_failures: $JULIA_VERSION == 'nightly'
  install_script:
    - sh -c "$(fetch https://raw.githubusercontent.com/ararslan/CirrusCI.jl/master/bin/install.sh -o -)"
  build_script:
    - cirrusjl build
  test_script:
    - cirrusjl test
  coverage_script:
    - cirrusjl coverage codecov coveralls
```

**NOTE**: [Coverage.jl](https://github.com/JuliaCI/Coverage.jl) does not yet support Cirrus
as a CI environment for coverage submission.
Once it does, the `cirrusjl coverage` step shown above will be verified to work properly.
In the meantime, the `cirrusjl coverage` step will always report success so as not to fail
builds that passed tests.

## Overview

`freebsd_instance` tells Cirrus which FreeBSD image you'd like to use.
You can use a `matrix` here to test on multiple FreeBSD versions, but as long as you're
using 12.2 or later, it shouldn't change much.

The version of Julia to install is specified by the environment variable `JULIA_VERSION`,
which can be set in a `matrix` (as in the template) to run parallel builds with different
versions of Julia.
Note though that **only Julia versions 0.7 and later are supported**.

Conditional build failures can be permitted using `allow_failures`.

The `cirrusjl` command invokes Julia with the proper options based on whether the project
being tested has a Project.toml file.
It features three subcommands:

* `build` installs the current package and runs `Pkg.build`,
* `test` runs the package's tests with bounds checking enabled, and
* `coverage` submits coverage to Codecov and/or Coveralls.

In turn, `cirrusjl coverage` takes 1 or 2 arguments, which must be `codecov` or `coveralls`
in any order.
