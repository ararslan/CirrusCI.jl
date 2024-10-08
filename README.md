# CirrusCI.jl

[![Cirrus](https://api.cirrus-ci.com/github/ararslan/CirrusCI.jl.svg?branch=master)](https://cirrus-ci.com/github/ararslan/CirrusCI.jl)

This repository contains utilities for using Julia on [Cirrus CI](https://cirrus-ci.org).
Cirrus is unique in the breadth of its support for systems and architectures.
Note that while Cirrus supports many systems, these utilities have only been validated to
work with FreeBSD, macOS, and Linux builds with Julia binaries matching the host's native
architecture.
That is, neither Windows nor using 32-bit Julia on a 64-bit host are currently supported.
For the time being, users are encouraged to continue to use
[GitHub Actions](https://github.com/julia-actions/setup-julia) in such cases, though
support here is planned for the future.

## Usage

Create a file called `.cirrus.yml` in the root directory of your Julia project and populate
it with one of the following templates, modifying as you see fit.

### One System

This example uses FreeBSD 13.3-RELEASE and retrieves the installer script using the
FreeBSD-specific command `fetch`.
When using this template for a different system, replace both the instance and the command
used for downloading the installer.
For Linux-based systems, `wget` is likely to be available by default, and `curl` should
be present on macOS.

```yaml
freebsd_instance:
  image_family: freebsd-13-3
task:
  name: FreeBSD
  env:
    matrix:
      - JULIA_VERSION: lts
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
    - cirrusjl coverage codecov
```

### Multiple Systems, Same Julia Versions

The desired images can be listed in a `matrix`.
This example builds on FreeBSD and on Ubuntu Linux with a 64-bit ARM processor.
A more complex `install_script` is required since there is no one command that can be
assumed to be available across platforms.
When editing this template to suit your needs, note that you may be able to simplify the
`install_script` if you know, for example, that `curl` is available in all images you're
using.
In the example below, we're checking for `apt` on Linux in order to handle the lack of
a downloader on the ARM Ubuntu containers, and looking for Linux specifically because
M1 Macs inexplicably have a program called `apt`.

```yaml
task:
  matrix:
    - name: FreeBSD
      freebsd_instance:
        image_family: freebsd-13-3
    - name: Linux ARMv8
      arm_container:
        image: ubuntu:latest
  env:
    matrix:
      - JULIA_VERSION: lts
      - JULIA_VERSION: 1
      - JULIA_VERSION: nightly
  allow_failures: $JULIA_VERSION == 'nightly'
  install_script: |
    URL="https://raw.githubusercontent.com/ararslan/CirrusCI.jl/master/bin/install.sh"
    if [ "$(uname)" = "Linux" ] && command -v apt; then
        apt update
        apt install -y curl
    fi
    if command -v curl; then
        sh -c "$(curl ${URL})"
    elif command -v wget; then
        sh -c "$(wget ${URL} -q -O-)"
    elif command -v fetch; then
        sh -c "$(fetch ${URL} -o -)"
    fi
  build_script:
    - cirrusjl build
  test_script:
    - cirrusjl test
  coverage_script:
    - cirrusjl coverage codecov
```

### Multiple Systems, Different Julia Versions

This example builds on FreeBSD with Julia 1.6, latest stable, and nightly; Alpine Linux
with latest stable only; and macOS M1 with latest stable only.

```yaml
task:
  matrix:
    - name: FreeBSD
      freebsd_instance:
        image_family: freebsd-13-3
      env:
        matrix:
          - JULIA_VERSION: lts
          - JULIA_VERSION: 1
          - JULIA_VERSION: nightly
    - name: Linux musl
      container:
        image: alpine:latest
      env:
        - JULIA_VERSION: 1
    - name: macOS M1
      macos_instance:
        image: ghcr.io/cirruslabs/macos-sonoma-base:latest
      env:
        - JULIA_VERSION: 1
  allow_failures: $JULIA_VERSION == 'nightly'
  install_script: |
    URL="https://raw.githubusercontent.com/ararslan/CirrusCI.jl/master/bin/install.sh"
    if [ "$(uname)" = "Linux" ] && command -v apt; then
        apt update
        apt install -y curl
    fi
    if command -v curl; then
        sh -c "$(curl ${URL})"
    elif command -v wget; then
        sh -c "$(wget ${URL} -q -O-)"
    elif command -v fetch; then
        sh -c "$(fetch ${URL} -o -)"
    fi
  build_script:
    - cirrusjl build
  test_script:
    - cirrusjl test
  coverage_script:
    - cirrusjl coverage codecov
```

### Code Coverage

Collection of code coverage is supported on all platforms.
Submission of coverage information to [Codecov](https://codecov.io) is supported using
Codecov's official command line interface, which should theoretically work on any platform.
Submission to [Coveralls](https://coveralls.io) is not supported, but requesting it does
not affect the build status.

> [!NOTE]
> `cirrusjl coverage codecov` can be very slow on FreeBSD because it needs to compile the
> Codecov CLI from source in every run. I've seen this take roughly 6-7 minutes. Most
> other platforms can use Codecov's prebuilt binaries, in which case this step takes just
> a few seconds.

### Projects in Subdirectories

By default, CirrusCI.jl will look for your Julia project in the root directory of the
repository.
For projects that reside in a subdirectory, for example as part of a monorepo, the
environment variable `JULIA_PROJECT_SUBDIR` can be used to specify the path to the project.

## Overview

Refer to the Cirrus documentation for information on the available execution environments.
CirrusCI.jl has been tested on a variety of systems not available from other CI providers,
including FreeBSD, Linux with musl, Linux with glibc on aarch64, and macOS M-series.
Note that certain combinations of platforms and Julia versions may be unavailable based on
when support was added to Julia.
For example, macOS M1 requires at least Julia 1.7 (1.8 if you want it to work) and Linux
with musl requires at least Julia 1.6.
In all cases, Julia 0.7 or later is required for use with CirrusCI.jl.

The version of Julia to install is specified by the environment variable `JULIA_VERSION`,
which can be set in a `matrix` (as in the templates) to run parallel builds with different
versions of Julia.
To use different sets of Julia versions for different platforms, set `env` individually
in each platform matrix entry.
The following formats are recognized for `JULIA_VERSION`:

- `1`: The most recent stable 1.x release. As of this writing, this is equivalent to `1.11`.
- `1.x` where `x` is a number: The latest patch release in the 1.x series. For example,
  specifying `1.6` will download v1.6.7.
- `1.x.y` where `x` and `y` are numbers, optionally followed by a prerelease specifier:
  The exact version specified. For example, `1.6.7` downloads v1.6.7, `1.11.0-rc4` downloads
  v1.11.0-rc4, and `6.9.420` will error.
- `lts`: Current long-term support release. Currently equivalent to `1.10`.
- `nightly`: Latest nightly build.

Conditional build failures can be permitted using `allow_failures`.

The `cirrusjl` command invokes Julia with the proper options based on whether the project
being tested has a Project.toml file.
(This is really only useful for ancient Julia packages which have somehow managed to avoid
switching from REQUIRE to Project.toml.)
It features three subcommands:

* `build` installs the current package and runs `Pkg.build`,
* `test` runs the package's tests with bounds checking enabled, and
* `coverage` collects coverage information and optionally submits it to Codecov and/or Coveralls.

In turn, `cirrusjl coverage` takes 1 or 2 arguments, which must be `codecov` or `coveralls`
in any order, specifying the provider(s) to which coverage information is submitted.
