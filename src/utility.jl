"""
    disable_polyester_threads(f::F)

A context manager function that disables Polyester threads without affecting the scheduling
of `Base.Treads.@threads`. Particularly useful for cases when Polyester has been used to
multithread an inner small problem that is now to be used in an outer embarassingly parallel
problem (in such cases it is best to multithread only at the outermost level).
"""
function disable_polyester_threads(f::F) where {F}
    t, r = request_threads(num_threads())
    f()
    foreach(free_threads!, r)
end
