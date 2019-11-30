using CirrusCI
using Test

@test iscirrus()
if VERSION >= v"1.4.0-DEV.0"
    @test false
end
