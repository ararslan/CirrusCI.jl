#!/bin/sh

set -e

stop() {
    echo -e "\033[0;31m[CIRRUSCI.JL]\033[0m: ${@}" >&2
    exit 1
}

info() {
    echo -e "\033[0;34m[CIRRUSCI.JL]\033[0m: ${@}"
}

### Sanity check the environment

if [ "${CIRRUS_CI}" != "true" ]; then
    stop "Script is not running on Cirrus CI"
fi

if [ "${CIRRUS_OS}" = "windows" ]; then
    OS="winnt"
elif [ "${CIRRUS_OS}" = "darwin" ]; then
    OS="mac"
elif [ "${CIRRUS_OS}" = "linux" ] && [ ! -z "$(ldd --version 2>&1 | grep -i musl)" ]; then
    OS="musl"
else
    OS="${CIRRUS_OS}"
fi

info "OS name: ${OS}"

### Validate the requested version

if [ -z "${JULIA_VERSION}" ]; then
    stop "JULIA_VERSION is not defined; don't know what to download"
fi

if [ "${JULIA_VERSION}" != "nightly" ]; then
    if [ -z "$(echo "${JULIA_VERSION}" | cut -d'.' -f 1 -s)" ]; then
        MAJOR="${JULIA_VERSION}"
        MINOR="8" # For JULIA_VERSION: 1 to point to latest stable release
        PATCH=""
        JULIA_VERSION="${MAJOR}.${MINOR}"
    else
        MAJOR="$(echo "${JULIA_VERSION}" | cut -d'.' -f 1)"
        MINOR="$(echo "${JULIA_VERSION}" | cut -d'.' -f 2)"
        PATCH="$(echo "${JULIA_VERSION}" | cut -d'.' -f 3)"
    fi

    if [ -z "${MAJOR}" ] || [ -z "${MINOR}" ]; then
        stop "Unrecognized Julia version"
    fi

    # NOTE: The cirrusjl logic assumes 0.7 or greater
    if [ ${MAJOR} -eq 0 ] && [ ${MINOR} -le 6 ]; then
        stop "CirrusCI.jl requires Julia 0.7 or later"
    fi
fi

# Determine the architecture and map it to what Julia calls it
ARCH="$(uname -m)"
case "${ARCH}" in
    "amd64") ARCH="x86_64"  ;;
    "i386")  ARCH="i686"    ;;
    "arm64") ARCH="aarch64" ;;
    "ppc64") ARCH="ppc64le" ;;
esac

info "Architecture name: ${ARCH}"

if [ "${ARCH}" = "x86_64" ]; then
    SHORT_ARCH="x64"
elif [ "${ARCH}" = "i686" ]; then
    SHORT_ARCH="x86"
else
    SHORT_ARCH="${ARCH}"
fi

if [ "${ARCH}" = "i686" ] || [ "${ARCH}" = "armv7l" ]; then
    WORD_SIZE="32"
else
    WORD_SIZE="64"
fi

if [ "${OS}" = "mac" ]; then
    if [ "${ARCH}" = "aarch64" ]; then
        SUFFIX="macaarch64.dmg"
    else
        SUFFIX="mac64.dmg"
    fi
elif [ "${OS}" = "winnt" ]; then
    SUFFIX="win${WORD_SIZE}.exe"
else
    if [ "${JULIA_VERSION}" = "nightly" ]; then
        if [ "${SHORT_ARCH}" != "${ARCH}" ]; then
            SUFFIX="${OS}${WORD_SIZE}.tar.gz"
        else
            SUFFIX="${OS}${ARCH}.tar.gz"
        fi
    else
        SUFFIX="${OS}-${ARCH}.tar.gz"
    fi
fi

if [ "${JULIA_VERSION}" = "nightly" ]; then
    URL="https://julialangnightlies-s3.julialang.org/bin/${OS}/${SHORT_ARCH}/julia-latest-${SUFFIX}"
else
    URL="https://julialang-s3.julialang.org/bin/${OS}/${SHORT_ARCH}/${MAJOR}.${MINOR}/julia-${JULIA_VERSION}"
    if [ -z "${PATCH}" ]; then
        URL="${URL}-latest"
    fi
    URL="${URL}-${SUFFIX}"
fi

### Download Julia

if [ -z "$(which curl)" ]; then
    info "Installing curl"
    if [ "${OS}" = "freebsd" ]; then
        pkg install -y curl
    elif [ "${OS}" = "musl" ]; then
        apk add curl
    elif [ ! -z "$(which apt)" ]; then
        apt update
        apt install -y curl
    else
        stop "Please open an issue on https://github.com/ararslan/CirrusCI.jl and tell me how to install curl on this OS"
    fi
fi

mkdir -p "${HOME}/julia"

info "Downloading Julia from ${URL}"

if [ "${OS}" = "mac" ]; then
    curl -s -L --retry 7 -o julia.dmg "${URL}"
    mkdir jlmnt
    hdiutil mount -readonly -mountpoint jlmnt julia.dmg
    cp -a jlmnt/*.app/Contents/Resources/julia "${HOME}/"
    hdiutil detach jlmnt
    rm -rf jlmnt julia.dmg
elif [ "${OS}" = "winnt" ]; then
    stop "don't know what to do"
else
    curl -s -L --retry 7 "${URL}" | tar -C "${HOME}/julia" -x -z --strip-components=1 -f -
fi

### Install and verify Julia

if [ ! -d /usr/local/bin ]; then
    # Some images don't have this directory by default and the default user isn't root,
    # which means we need `sudo` to install to `/usr/local/bin`, assuming `sudo` is
    # available. Empirically, these conditions seems only to be the case on macOS.
    if [ $(id -u) -ne 0 ] && [ ! -z "$(command -v sudo)" ]; then
        sudo mkdir -p /usr/local/bin
        sudo chown -R $(id -un) /usr/local/bin
    else
        mkdir -p /usr/local/bin
    fi
fi

ln -fs "${HOME}/julia/bin/julia" /usr/local/bin/julia

julia --color=yes -e "using InteractiveUtils; versioninfo()"

### Install utilities

# Throw out trailing .jl, assume the name is otherwise a valid Julia package name
JLPKG="$(echo "${CIRRUS_REPO_NAME}" | cut -d'.' -f 1)"

cat > /usr/local/bin/cirrusjl <<EOF
#!/bin/sh

set -e

hasproj() {
    [ -f "Project.toml" ] || [ -f "JuliaProject.toml" ]
}

export JULIA_PROJECT="@."

cd "${CIRRUS_WORKING_DIR}"
if [ -e ".git/shallow" ]; then
    git fetch --unshallow
fi

INPUT="\$1"

case "\${INPUT}" in
    "build")
        if hasproj; then
            julia --color=yes --project=. -e "
                using Pkg
                if VERSION >= v\"1.1.0\"
                    Pkg.build(verbose=true)
                else
                    Pkg.build()
                end
            "
        else
            julia --color=yes -e "
                using Pkg
                Pkg.add(PackageSpec(name=\"${JLPKG}\", path=pwd()))
                if VERSION >= v\"1.1.0\"
                    Pkg.build(\"${JLPKG}\", verbose=true)
                else
                    Pkg.build(\"${JLPKG}\")
                end
            "
        fi
        ;;

    "test")
        if hasproj; then
            julia --check-bounds=yes --color=yes --project=. -e "
                using Pkg
                Pkg.test(coverage=true)
            "
        else
            julia --check-bounds=yes --color=yes -e "
                using Pkg
                Pkg.test(\"${JLPKG}\", coverage=true)
            "
        fi
        ;;

    "coverage")
        shift
        CODECOV=""
        COVERALLS=""
        while :; do
            case "\$1" in
                "codecov")
                    CODECOV="yes"
                    ;;
                "coveralls")
                    COVERALLS="yes"
                    ;;
                *)
                    break
                    ;;
            esac
            shift
        done
        # Based on julia-actions/julia-processcoverage/main.jl
        julia --color=yes -e '
            using Pkg
            Pkg.activate("coveragetempenv"; shared=true)
            Pkg.add("CoverageTools")
            using CoverageTools
            directories = get(ENV, "INPUT_DIRECTORIES", "src")
            dirs = filter!(!isempty, split(directories, ","))
            for dir in dirs
                isdir(dir) || error("directory \$dir not found!")
            end
            pfs = mapreduce(process_folder, vcat, dirs)
            LCOV.writefile("lcov.info", pfs)
        '
        if [ ! -z "\${CODECOV}" ]; then
            if [ "${OS}" = "freebsd" ]; then
                # See https://github.com/codecov/uploader/issues/849 for FreeBSD
                echo "[CIRRUSCI.JL] Skipping Codecov submission on this platform, sorry :("
            else
                if [ "${OS}" = "musl" ]; then
                    CODECOV_OS="alpine"
                elif [ "${OS}" = "mac" ]; then
                    CODECOV_OS="macos"
                else
                    CODECOV_OS="${OS}"
                fi
                CODECOV_URL="https://uploader.codecov.io/latest/\${CODECOV_OS}/codecov"
                echo "[CIRRUSCI.JL] Downloading the Codecov uploader from \${CODECOV_URL}"
                curl -L "\${CODECOV_URL}" -o /usr/local/bin/codecov
                chmod +x /usr/local/bin/codecov
                if [ "${OS}" = "mac" ] && [ "${ARCH}" = "aarch64" ]; then
                    sudo softwareupdate --install-rosetta --agree-to-license
                    CODECOV_EXE="arch -x86_64 codecov"
                elif [ "${OS}" = "linux" ] && [ "${ARCH}" != "x86_64" ] && [ ! -z "\$(which apt)" ]; then
                    apt install -y qemu-user
                    CODECOV_EXE="qemu-x86_64 /usr/local/bin/codecov"
                else
                    CODECOV_EXE="codecov"
                fi
                if [ ! -z "\${CODECOV_TOKEN}" ]; then
                    CODECOV_EXE="\${CODECOV_EXE} -t \${CODECOV_TOKEN}"
                fi
                \${CODECOV_EXE} \
                    -R "${CIRRUS_WORKING_DIR}" \
                    --file lcov.info \
                    --source "github.com/ararslan/CirrusCI.jl" \
                    --verbose
            fi
        fi
        if [ ! -z "\${COVERALLS}" ]; then
            echo "[CIRRUSCI.JL] Coveralls is not currently supported"
        fi
        ;;

    *)
        echo "Usage: cirrusjl <build|test|coverage>" >&2
        exit 1
        ;;
esac
EOF

chmod +x /usr/local/bin/cirrusjl
