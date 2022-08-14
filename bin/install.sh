#!/bin/sh

set -e

stop() {
    echo "$@" >&2
    exit 1
}

### Sanity check the environment

if [ "${CIRRUS_CI}" != "true" ]; then
    stop "Script is not running on Cirrus CI"
fi

# TODO: Remove this check and allow other OSes
if [ "$(uname -s)" != "FreeBSD" ]; then
    stop "This script currently only supports FreeBSD"
fi

if [ "${CIRRUS_OS}" = "windows" ]; then
    OS="winnt"
elif [ "${CIRRUS_OS}" = "darwin" ]; then
    OS="mac"
else
    OS="${CIRRUS_OS}"
fi

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

    # We didn't have fully functioning binaries for FreeBSD until 0.7
    # XXX: The cirrusjl logic assumes 0.7 or greater
    if [ "${OS}" = "freebsd" ] && [ ${MAJOR} -eq 0 ] && [ ${MINOR} -le 6 ]; then
        stop "FreeBSD requires Julia 0.7 or later"
    fi
fi

### Download Julia

if [ "${OS}" = "freebsd" ]; then
    pkg install -y curl
fi

# TODO: Determine whether Cirrus supports images other than 64-bit
if [ "${OS}" = "mac" ]; then
    SUFFIX="mac64.dmg"
elif [ "${OS}" = "winnt" ]; then
    SUFFIX="win64.exe"
else
    if [ "${JULIA_VERSION}" = "nightly" ]; then
        SUFFIX="${OS}64.tar.gz"
    else
        SUFFIX="${OS}-x86_64.tar.gz"
    fi
fi

if [ "${JULIA_VERSION}" = "nightly" ]; then
    URL="https://julialangnightlies-s3.julialang.org/bin/${OS}/x64/julia-latest-${SUFFIX}"
else
    URL="https://julialang-s3.julialang.org/bin/${OS}/x64/${MAJOR}.${MINOR}/julia-${JULIA_VERSION}"
    if [ -z "${PATCH}" ]; then
        URL="${URL}-latest"
    fi
    URL="${URL}-${SUFFIX}"
fi

mkdir -p "${HOME}/julia"

if [ "${OS}" = "mac" ]; then
    curl -s -L --retry 7 -o julia.dmg "${URL}"
    mkdir jlmnt
    hdiutil mount -readonly -mountpoint jlmnt julia.dmg
    cp -a jlmnt/*.app/Contents/Resources/julia "${HOME}"
    hdiutil detach jlmnt
    rm -rf jlmnt julia.dmg
elif [ "${OS}" = "winnt" ]; then
    stop "don't know what to do"
else
    curl -s -L --retry 7 "${URL}" | tar -C "${HOME}/julia" -x -z --strip-components=1 -f -
fi

### Install and verify Julia

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
        while :; do
            case "\$1" in
                "coveralls")
                    echo "Submitting coverage to Coveralls is not supported" >&2
                    exit 1
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
        if [ ! -z "\${CODECOV_TOKEN}" ]; then
            SET_TOKEN="-t \${CODECOV_TOKEN}"
        else
            SET_TOKEN=""
        fi
        timeout \
            --signal SIGTERM \
            --preserve-status \
            --kill-after 1m \
            5m \
            /compat/linux/bin/strace -irTyCwf \
                codecov \
                    \${SET_TOKEN} \
                    -R "${CIRRUS_WORKING_DIR}" \
                    --file lcov.info \
                    --source "github.com/ararslan/CirrusCI.jl" \
                    --verbose
        ;;

    *)
        echo "Usage: cirrusjl <build|test|coverage>" >&2
        exit 1
        ;;
esac
EOF

chmod +x /usr/local/bin/cirrusjl

# Setup Linux emulation in order to use the Codecov uploader
service linux onestart || true
pkg install -y emulators/linux_base-c7 linux-c7-strace
tee -a /etc/fstab <<EOF
linprocfs	/compat/linux/proc	linprocfs	rw	0	0
linsysfs	/compat/linux/sys	linsysfs	rw	0	0
tmpfs	/compat/linux/dev/shm	tmpfs	rw,mode=1777	0	0
EOF
mount /compat/linux/proc
mount /compat/linux/sys
mount /compat/linux/dev/shm
service linux onestart

# Install the Codecov uploader (https://docs.codecov.com/docs/codecov-uploader)
curl "https://uploader.codecov.io/latest/linux/codecov" --output "/usr/local/bin/codecov"
chmod +x /usr/local/bin/codecov
