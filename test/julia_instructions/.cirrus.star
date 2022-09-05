load("../../lib.star", "julia_instructions")
load("github.com/cirrus-modules/helpers", "task", "freebsd_instance")

def main(ctx):
    return [task("No coverage", freebsd_instance("freebsd-13-0"),
                 instructions=julia_instructions("FreeBSD")),
            task("Codecov", freebsd_instance("freebsd-13-0"),
                 instructions=julia_instructions("FreeBSD", coverage="codecov"))]
