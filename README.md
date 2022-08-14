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
    - cirrusjl coverage
```

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
* `coverage` submits coverage to Codecov.

### Code Coverage

Previously, the `coverage` subcommand was effectively a no-op, as
[Coverage.jl](https://github.com/JuliaCI/Coverage.jl) did not (and as of this writing
still does not) support Cirrus CI, so the status of the coverage step was always ignored.
Despite this, the implementation of `cirrusjl coverage` formerly permitted 1 or 2
arguments: `codecov` or `coveralls` in any order.

**This has changed**: the status is no longer ignored, and specifying `coveralls` now
emits an error.
On the other hand, `codecov` is now supported using Codecov's official uploader.
Additionally, users may now simply use `cirrusjl coverage`, which is equivalent to
`cirrusjl coverage codecov`.

Contributions are welcome should anyone have an interest in using Coveralls for Julia
code coverage on Cirrus.
As Coveralls does not maintain a centralized uploader, support for Cirrus must first land
in Coverage.jl.
