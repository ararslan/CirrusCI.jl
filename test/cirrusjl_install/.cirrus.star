load("../../lib.star", "cirrusjl_install")
load("github.com/cirrus-modules/helpers", "task", "windows_container", "freebsd_instance",
     "macos_instance", "container", "arm_container")

def _task(name, instance):
    os = name.split(" ")[0]
    return task(name, instance, instructions=[cirrusjl_install(os)])

def main(ctx):
    return [_task("FreeBSD", freebsd_instance("freebsd-13-0-release-amd64")),
            _task("Linux AArch64", arm_container("ubuntu:latest")),
            _task("Linux musl", container("alpine:3.14")),
            _task("Windows", windows_container("cirrusci/windowsservercore")),
            _task("macOS", macos_instance("big-sur-xcode"))]
