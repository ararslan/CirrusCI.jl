load("cirrus", environ="env")
load("github.com/cirrus-modules/helpers", "powershell", "script", "task")

def cirrusjl_install():
    base = "https://raw.githubusercontent.com/ararslan/CirrusCI.jl/master/bin"
    os = environ["CIRRUS_OS"]
    if os == "windows":
        file = base + "/install.ps1"
        cmd = "iex ((New-Object System.Net.WebClient).DownloadString('%s'))" % file
        return powershell("install", cmd)
    file = base + "/install.sh"
    if os == "darwin":
        download = "curl " + file
    elif os == "freebsd":
        download = "fetch %s -o -" % file
    else:
        download = "wget %s -q -O-" % file
    cmd = "sh -c \"$(%s)\"" % download
    return script("install", cmd)

def julia_instructions(coverage=None):
    steps = [cirrusjl_install(),
             script("build", "cirrusjl build"),
             script("test", "cirrusjl test")]
    if coverage:
        steps.append(script("coverage", "cirrusjl coverage %s" % coverage))
    return steps

def julia_tasks(versions, instances, env={}, coverage=None, allow_failures=None):
    tasks = []
    instructions = julia_instructions(coverage=coverage)
    for instance in instances:
        for version in versions:
            v = {"JULIA_VERSION": version}.update(env)
            t = task(name="", instance=instance, instructions=instructions, env=v)
            tasks.append(t)
    return tasks
