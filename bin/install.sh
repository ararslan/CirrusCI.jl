#!/bin/sh

set -e
set -x

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
elif [ "${JULIA_VERSION}" = "nightly" ] && [ "${OS}" = "freebsd" ]; then
    # TODO: Remove this once we have working FreeBSD nightlies
    stop "Nightly binaries are not currently available for FreeBSD"
fi

MAJOR="$(echo "${JULIA_VERSION}" | cut -d'.' -f 1)"
MINOR="$(echo "${JULIA_VERSION}" | cut -d'.' -f 2)"
PATCH="$(echo "${JULIA_VERSION}" | cut -d'.' -f 3)"

if [ -z "${MAJOR}" ] || [ -z "${MINOR}" ]; then
    stop "Unrecognized Julia version"
fi

# We didn't have fully functioning binaries for FreeBSD until 0.7
if [ "${OS}" = "freebsd" ] && [ ${MAJOR} -eq 0 ] && [ ${MINOR} -le 6 ]; then
    stop "FreeBSD requires Julia 0.7 or later"
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
    # TODO: I have no idea
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
if [ -a ".git/shallow" ]; then
    git fetch --unshallow
fi

INPUT="\$1"

case "\${INPUT}" in
    "build")
        if hasproj; then
            julia --color=yes -e "
                if VERSION < v\"0.7.0-DEV.5183\"
                    Pkg.clone(pwd())
                    Pkg.build(\"${JLPKG}\")
                else
                    using Pkg
                    if VERSION >= v\"1.1.0\"
                        Pkg.build(verbose=true)
                    else
                        Pkg.build()
                    end
                end
            "
        else
            julia --color=yes -e "
                VERSION >= v\"0.7.0-DEV.5183\" && using Pkg
                Pkg.clone(pwd()) # NOTE: emits a deprecation warning
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
            julia --check-bounds=yes --color=yes -e "
                if VERSION < v\"0.7.0-DEV.5183\"
                    Pkg.test(\"${JLPKG}\", coverage=true)
                else
                    using Pkg
                    Pkg.test(coverage=true)
                end
            "
        else
            julia --check-bounds=yes --color=yes -e "
                VERSION >= v\"0.7.0-DEV.5183\" && using Pkg
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
                    CODECOV="Codecov.submit(p)"
                    ;;
                "coveralls")
                    COVERALLS="Coveralls.submit(p)"
                    ;;
                *)
                    break
                    ;;
            esac
            shift
        done
        if hasproj; then
            julia --color=yes -e "
                if VERSION < v\"0.7.0-DEV.5183\"
                    cd(Pkg.dir(\"${JLPKG}\"))
                else
                    using Pkg
                end
                Pkg.add(\"Coverage\")
                using Coverage
                p = process_folder()
                \${CODECOV}
                \${COVERALLS}
            " || true
        else
            julia --color=yes -e "
                VERSION >= v\"0.7.0-DEV.5183\" && using Pkg
                cd(Pkg.dir(\"${JLPKG}\")) # NOTE: emits a deprecation warning
                Pkg.add(\"Coverage\")
                using Coverage
                p = process_folder()
                \${CODECOV}
                \${COVERALLS}
            " || true
        fi
        ;;

    *)
        echo "Usage: cirrusjl <build|test|coverage>" >&2
        exit 1
        ;;
esac
EOF

chmod +x /usr/local/bin/cirrusjl
