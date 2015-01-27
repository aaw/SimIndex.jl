# SimIndex

[![Build Status](https://travis-ci.org/aaw/SimIndex.jl.svg?branch=master)](https://travis-ci.org/aaw/SimIndex.jl)

Given a set of items (strings, documents, vectors) and a distance measure on
pairs of those items (edit distance, cosine distance, Euclidean distance),
SimIndex builds an index of the k closest items for every item in the set.

The script in `examples/words.jl` loads the set of English words in the file
`/usr/share/dict/words` and builds a SimIndex using edit distance:

```
$ julia ~/.julia/v0.3/SimIndex/examples/words.jl
Loaded 73034 words from /usr/share/dict/words
Sampling vertices for initial neighbor lists...100% Time: 0:00:07
Compiling index...100% Time: 0:07:02
Enter a word to see similar words with respect to edit distance.
Enter '?' to run with a random word.

> julia
july (2.0)
nubia (2.0)
judea (2.0)
gala (3.0)
junks (3.0)

>
```

Building such an index by exhaustively comparing each word with all other words
would take over 2.5 billion distance calculations. SimIndex uses a
[well-known heuristic][] to build a good approximation to the exact index that
avoids exhaustively computing the distance between each pair.

The heuristic works roughly like this: SimIndex maintains a neighbor list of
the k closest items seen for each item in the index. Initially, these lists are
all populated randomly. To improve the quality of the index, each iteration of
the index compilation chooses an item `u` at random, samples one of it's
current neighbors `v` at random, then samples one of `v`'s current neighbors
`w` at random. `u` and `w` are then introduced to each other: if `w` is closer
than any of `u`'s current neighbors, `w` moves into `u`'s neighbor list and
pushes out one of `u`'s current neighbors. Similarly, `u` gets a chance to move
into `w`'s current list of neighbors if `w` is closer to `u` than at least one
of `u`'s neighbors.

In practice, this process very quickly converges to a near-optimal index.
SimIndex uses a convergence criterion similar to the one proposed in "[Efficient
K-Nearest Neighbor Graph Construction for Generic Similarity Measures][]" by
Dong, Charikar, and Li: run a fixed number of iterations per epoch and count the
number of times a neighbor list is updated. When this number falls
below a threshold, stop the compilation.

### Installing the package

```
julia> Pkg.clone("git://github.com/aaw/SimIndex.jl.git")
```

SimIndex depends on an unreleased patch to the [ProgressMeter package][]. You
can manually pull the latest into your environment by changing directories to
the directory where package is installed:

```
julia> cd(Pkg.dir("ProgressMeter"))
```

Next, type a semicolon at the Julia prompt to switch to shell mode, then run
a `git pull` to pull the latest from `master`:

```
shell> git pull origin master
```

Finally, run the tests to make sure everything is set up okay:

```
julia> Pkg.test("SimIndex")
```

### Using the package

Create an index by passing a Dict that maps labels to values:

```
julia> using SimIndex

julia> si = SimIndex.Index([char(i) => [i,i,i,i] for i=65:91], k=5)
...

julia> SimIndex.k_nearest_neighbors(si, 'Z')
5-element Array{(Char,Float64),1}:
 ('Y',2.0)
 ('X',4.0)
 ('W',6.0)
 ('V',8.0)
 ('U',10.0)

julia> SimIndex.k_nearest_neighbors(si, 'M')
5-element Array{(Char,Float64),1}:
 ('N',2.0)
 ('L',2.0)
 ('K',4.0)
 ('O',4.0)
 ('J',6.0)
```

The `Index` constructor also accepts two keyword arguments:

* `k`: The number of neighbors you want to compute for each element in the index. Default
       is 10.
* `d`: The distance function. This function should take two values and return a float
       that represents the distance between those two elements. This function should
       give consistent answers when applied to the same pair of elements, but no
       other restrictions (e.g., the triangle inequality) are imposed. Default is
       Euclidean distance on vectors.

For simple applications where the item labels are also the values (for example,
comparing words by edit distance), you can just pass an array to the `Index`
constructor instead of passing a label-to-value mapping:

```
julia> words = ["foo", "bar", "biz", "baz", ...

julia> si = SimIndex.Index(words, d=edit_distance)
```

The `Index` constructor compiles the index, but you can also recompile to increase
accuracy as needed:

```
julia> SimIndex.compile!(si)
```

`compile!` takes a second parameter, `delta`, that determines when the index has
converged. Each epoch of compilation on an index containing N items samples
N pairs of items, introduces those pairs to each other, and adds 1 to a counter
whenever any of those introductions result in improvements to neighbor sets. `delta`
is a threshold: once the number of improvements in an epoch divided by N drops
below `delta`, the index is assumed to have converged and compilation stops. `delta`
defaults to 0.05. Decreasing `delta` increases the quality of the index and the amount
of time index compilation takes.

You can retrieve nearest neighbors of an element from a compiled index
using the `k_nearest_neighbors` function, which returns an array of label, distance
pairs, sorted by ascending distance:

```
julia> SimIndex.k_nearest_neigbhors(si, "foo")
5-element Array{(Char,Float64),1}:
 ('bar',1.0)
 ('baz',2.0)
 ('biz',3.0)
 ('buz',4.0)
 ('boz',4.0)
```

A SimIndex can be modified after it's compiled, using `push!` to change or add
values for a label:

```
julia> SimIndex.push!(si, "foo", [1,2,3,4])
```

After new values have been pushed, the index will need to be `compile!`d again
before you can use it.

### Measuring Index Quality

`SimIndex` includes a function `test_error_ratio` that you can use to measure
the quality of your index. The error ratio of an item's neighbor set is the average
of the ratios of distances of all elements in the index to their ideal values. If
the error ratio of an item is 1.0, the index is exact. If the error ratio is 2.0,
then on average, the index is returning neighbors that are twice as far away as
the actual nearest neighbors of the item. By default, we test the error ratio on
50 items from the index and return the average of those 50 measurements, but you
can change this by passing a different value to the second parameter of
`test_error_ratio`:

```
julia> SimIndex.test_error_ratio(si, 100)
1.093417712842713
```

If the error ratio isn't good enough, just compile the index again or compile it
with a smaller delta value.

[well-known heuristic] http://arvindn.livejournal.com/93678.html
[Efficient K-Nearest Neighbor Graph Construction for Generic Similarity Measures] http://www.cs.princeton.edu/cass/papers/www11.pdf
[ProgressMeter package] https://github.com/timholy/ProgressMeter.jl
