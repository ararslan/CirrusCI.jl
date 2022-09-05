load("cirrus", environ="env")
load("github.com/cirrus-modules/helpers", "powershell", "script", "task")

def _os_from_instance(instance):
    # Instances are `dict`s formatted as `{ type: descriptors }` where `type` is
    # one of Cirrus' predefined execution environment names
    if instance.get("container") or instance.get("arm_container"):
        return "Linux"
    elif instance.get("macos_instance"):
        return "macOS"
    elif instance.get("freebsd_instance"):
        return "FreeBSD"
    elif instance.get("windows_container"):
        return "Windows"
    else:
        return "Unknown OS"

def cirrusjl_install(os):
    base = "https://raw.githubusercontent.com/ararslan/CirrusCI.jl/master/bin"
    if os == "Windows":
        file = base + "/install.ps1"
        cmd = "iex ((New-Object System.Net.WebClient).DownloadString('%s'))" % file
        return powershell("install", cmd)
    file = base + "/install.sh"
    if os == "macOS":
        download = "curl " + file
    elif os == "FreeBSD":
        download = "fetch %s -o -" % file
    else:
        download = "wget %s -q -O-" % file
    cmd = "sh -c \"$(%s)\"" % download
    return script("install", cmd)

def julia_instructions(os, coverage=None):
    steps = [cirrusjl_install(os),
             script("build", "cirrusjl build"),
             script("test", "cirrusjl test")]
    if coverage:
        steps.append(script("coverage", "cirrusjl coverage %s" % coverage))
    return steps

def julia_tasks(versions, instances, env={}, coverage=None, allow_failures=None):
    tasks = []
    for instance in instances:
        os = _os_from_instance(instance)
        instructions = julia_instructions(os, coverage=coverage)
        for version in versions:
            v = {"JULIA_VERSION": version}.update(env)
            t = task(name=os, instance=instance, instructions=instructions, env=v)
            tasks.append(t)
    return tasks
