tests = ["tests"]

for t in tests
    fp = string(t, ".jl")
    println("* running $fp ...")
    include(fp)
end
