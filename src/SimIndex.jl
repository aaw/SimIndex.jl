module SimIndex

export Index, push!, compile!, k_nearest_neighbors, test_error_ratio

using ProgressMeter
using Base.Collections  # For PriorityQueue.
using Iterators         # For drop.
import Distances
import Base.push!       # We overload push! on SimIndex, need Base.push! as well.

type Index{KeyType, ValueType}
    k::Int  # Number of neighbors
    a::Int  # Size of actual neighborset (> k for convergence)
    distance::Function
    items::Dict{KeyType, ValueType}
    index::Dict{KeyType, PriorityQueue{KeyType, Float64}}
    compiled_index::Dict{KeyType, Array{Pair{KeyType, Float64}, 1}}
    dirty::Bool  # Have elements been pushed to the index since a successful compile?
end

function Index(items; k=10, d=Distances.euclidean)
    if !(typeof(items) <: Dict)
        items = [x => x for x in items]
    end
    KeyType = eltype(keys(items))
    ValueType = eltype(values(items))
    index = Dict{KeyType, PriorityQueue{KeyType, Float64}}()
    compiled_index = Dict{KeyType, Array{Pair{KeyType, Float64}, 1}}()
    si = Index{KeyType, ValueType}(k, 2 * k, d, items, index, compiled_index, true)
    compile!(si)
end

function push!(s::Index, value)
    s.items[value] = value
    s.dirty = true
end

function push!(s::Index, key, value)
    s.items[key] = value
    s.dirty = true
end

function compile!(s::Index, delta::Float64=0.05)
    KeyType = eltype(keys(s.items))
    recompile = (length(s.compiled_index) != 0)
    vs = [k for k in keys(s.items)]
    nvs = length(vs)

    # Initialize the neighbor list. If we've never compiled an index before,
    # we'll sample s.a neighbors at random for each vertex's neighbor list. If
    # this is a recompile of an existing index, we'll keep s.k of the best
    # neighbors for each vertex and sample s.a - s.k neighbors.
    if s.a > nvs - 1
        error("k too large: can't sample $(s.a) neighbors from a set of size $(nvs - 1)")
    end
    p = Progress(nvs, 1, "Sampling vertices for initial neighbor lists...")
    for (v, val) in s.items
        if recompile && haskey(s.compiled_index, v)
            q = [x => d for (x,d) in s.compiled_index[v][1:s.k]]
            s.index[v] = PriorityQueue(q, Base.Sort.Reverse)
            for x in sample(vs, s.a - s.k, union(Set(keys(q)), Set([v])))
                enqueue!(s.index[v], x, s.distance(val, s.items[x]))
            end
        else
            sampled = sample(vs, s.a, Set([v]))
            s.index[v] = PriorityQueue(
              [x => s.distance(val, s.items[x])::Float64 for x in sampled],
              Base.Sort.Reverse)
        end
        next!(p)
    end
    empty!(s.compiled_index)

    res = 1.01  # Decrease res to have more granular progress displayed.
    steps = round(Int, ceil(log(res, 2/delta)))  # Number of steps in progress.
    thres = 2.0  # Next milestone for displaying progress.
    ratio = 2.0  # Current progress (c / nvs)
    p = Progress(steps, 1, "Compiling index...")
    while true
        c = 0
        for j=1:nvs
            u = vs[rand(1:nvs)]
            w = rand_key(s.index[rand_key(s.index[u])])
            if u == w
                continue
            end
            d = s.distance(s.items[u], s.items[w])
            for (x,y) in [(u,w), (w,u)]
                _, maxd = peek(s.index[x])
                if maxd > d
                    c += update_priority_queue(s, x, y, d)
                end
            end
        end
        if c == 0 || ratio < delta
            break
        end
        if c / nvs < ratio
            ratio = c / nvs
        end
        while ratio < thres / res
            next!(p)
            thres = thres / res
        end
    end
    finish!(p)
    generate_compiled_index!(s)
end

function rand_key(d)
    first(take(drop(keys(d), rand(1:length(d)) - 1), 1))
end

# Update SimIndex s to add y to x's nearest neighbors if d is less than one of
# x's existing nearest neighbors' distances. Return 1 if y was added to x's
# nearest neighbors, 0 otherwise.
function update_priority_queue(s, x, y, d)
    try enqueue!(s.index[x], y, d)
    catch
        # y is already in s.index[x]
        return 0
    end
    dequeue!(s.index[x])
    return 1
end

# Sample k elements uniformly from the stream xs while avoiding items in the avoid set.
function sample(xs, k, avoid)
    s = Set{eltype(xs)}()
    nx = length(xs)
    while length(s) < k
        x = xs[rand(1:nx)]
        if !in(x, avoid)
            push!(s, x)
        end
    end
    return [x for x in s]
end

function generate_compiled_index!(s::Index)
    KeyType = eltype(keys(s.index))
    for (key, vals) in s.index
        xs = Pair{KeyType, Float64}[]
        while true
            try
                push!(xs, peek(vals))
                dequeue!(vals)
            catch
                break
            end
        end
        reverse!(xs)
        s.compiled_index[key] = xs
    end
    empty!(s.index)
    s.dirty = false
    s
end

function k_nearest_neighbors(s::Index, key; k=s.k)
    if s.dirty
        error("Index needs to be compiled.")
    end
    vals = get(s.compiled_index, key, Union{})
    if vals == Union{}
        return Union{}
    end
    return vals[1:min(length(vals), k)]
end

function test_error_ratio(s::Index, n=50)
    ks = [k for k in keys(s.items)]
    KeyType = eltype(ks)
    ratios = Float64[]
    for i=1:n
        k = ks[rand(1:end)]
        v = s.items[k]
        q = PriorityQueue(Dict{KeyType, Float64}(), Base.Sort.Reverse)
        for (k2, v2) in s.items
            if k2 == k
                continue
            end
            d = s.distance(v, v2)
            enqueue!(q, k2, d)
            if length(q) > s.k
                dequeue!(q)
            end
        end
        # Accumulate key, distance pairs
        xs = Pair{KeyType, Float64}[]
        while true
            try
                push!(xs, peek(q))
                dequeue!(q)
            catch
                break
            end
        end
        reverse!(xs)
        push!(ratios, error_ratio(xs, k_nearest_neighbors(s, k)))
    end
    mean(ratios)
end

function error_ratio(actual, approx)
    if length(actual) != length(approx)
        error("Arrays passed to error_ratio have different lengths")
    end
    xs = Float64[]
    for i=1:length(actual)
        push!(xs, (approx[i].second + eps()) / (actual[i].second + eps()))
    end
    mean(xs)
end

end # module
