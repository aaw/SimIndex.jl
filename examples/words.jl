# An interactive demo of SimIndex. Creates an index of similar English words
# based on edit distance. For each word in the /usr/share/dict/words file, we
# use SimIndex to compute a set of 5 words within a small edit distance
#
# Run this with the julia interpreter ("julia examples/words.jl") after
# installing SimIndex (Pkg.install("git://github.com/aaw/SimIndex.jl.git")).

import SimIndex

function load_words()
    wordfile = "/usr/share/dict/words"
    words = ASCIIString[]
    open(wordfile) do f
        for word in eachline(f)
            word = strip(word)
            if !endswith(word, "'s")
                push!(words, lowercase(word))
            end
        end
    end
    println("Loaded $(length(words)) words from $wordfile")
    words
end

# Edit distance, copied from Julia's base/docs.jl.
function levenshtein(s1, s2)
    a, b = collect(s1), collect(s2)
    m = length(a)
    n = length(b)
    d = Array(Float64, m+1, n+1)

    d[1:m+1, 1] = 0:m
    d[1, 1:n+1] = 0:n

    for i = 1:m, j = 1:n
        d[i+1,j+1] = min(d[i  , j+1] + 1,
                         d[i+1, j  ] + 1,
                         d[i  , j  ] + (a[i] != b[j]))
    end

    return d[m+1, n+1]
end

words = load_words()
coords = [w => w for w in words]
si = SimIndex.Index(coords, k=5, d=levenshtein)

input = " "
println("Enter a word to see similar words with respect to edit distance.")
println("Enter '?' to run with a random word.")
println("")
while true
    print("> ")
    word = strip(readline(STDIN))
    if word == ""
        break
    elseif word == "?"
        word = words[rand(1:length(words))]
        println("$word")
    elseif !haskey(coords, word)
        println("$word not found. Try another one.")
        println("")
        continue
    end
    for (w,d) in SimIndex.k_nearest_neighbors(si, word)
        println("$w ($d)")
    end
    println("")
end
