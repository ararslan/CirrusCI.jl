module CirrusCI

export iscirrus

iscirrus() = parse(Bool, get(ENV, "CIRRUS_CI", "false"))

end # module
