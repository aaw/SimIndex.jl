using SimIndex
using Base.Test
using Distances

println("Building an index on 1,000 1-dimensional points with Euclidean distance...")
si = SimIndex.Index(collect(1:1000), k=20, d=euclidean)
er = SimIndex.test_error_ratio(si)
println("Error ratio: $(er)")
println("")
@test er < 2.0

println("Building an index on 8,000 5-dimensional points with Euclidean distance...")
si = SimIndex.Index([string(i) => rand(5) for i=1:8000])
er = SimIndex.test_error_ratio(si)
println("Error ratio: $(er)")
println("")
@test er < 2.0

println("Building an index on 5,000 5-dimensional points with Cosine distance...")
coords = [string(i) => rand(5) for i=1:5000]
si = SimIndex.Index(coords, k=10, d=cosine_dist)
er = SimIndex.test_error_ratio(si)
println("Error ratio: $(er)")
println("")
@test er < 2.0

println("Testing incremental index construction...")
si = SimIndex.Index(collect(1:500), k=20, d=euclidean)
for i=501:1000
    push!(si, i)
end
compile!(si)
er = SimIndex.test_error_ratio(si)
println("Error ratio: $(er)")
println("")
@test er < 2.0

println("Testing index recompilation...")
si = SimIndex.Index(collect(1:1000), k=20, d=euclidean)
first_er = SimIndex.test_error_ratio(si)
println("Error ratio: $(er)")
compile!(si, 0.25)
second_er = SimIndex.test_error_ratio(si)
println("Error ratio: $(er)")
compile!(si, 0.05)
third_er = SimIndex.test_error_ratio(si)
println("Error ratio: $(er)")
@test first_er >= second_er
@test second_er >= third_er
@test third_er >= 1.0
