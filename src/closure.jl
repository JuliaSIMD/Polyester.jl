function getgensym!(defined::Dict{Symbol,Symbol}, s::Symbol)
  snew = get!(defined, s) do
    gensym(s)
  end
  snew ≢ s && (defined[snew] = snew)
  return snew
end

extractargs!(arguments::Vector{Symbol}, defined::Dict{Symbol,Symbol}, sym, mod) = nothing
# function extractargs!(arguments::Vector{Symbol}, defined::Dict{Symbol,Symbol}, sym::Symbol, mod)
#   if ((sym ∉ keys(defined)) && sym ∉ (:nothing, :(+), :(*), :(-), :(/), :(÷), :(<<), :(>>), :(>>>), :zero, :one)) && !Base.isdefined(mod, sym)
#     @show getgensym!(defined, sym)
#     @assert false
#     push!(arguments, getgensym!(defined, sym))
#   end
#   nothing
# end
function define_tup!(defined::Dict{Symbol,Symbol}, ex::Expr)
  for (i, a) ∈ enumerate(ex.args)
    if a isa Symbol
      ex.args[i] = getgensym!(defined, a)
    else
      define_tup!(defined, a)
    end
  end
end
function define1!(defined::Dict{Symbol,Symbol}, x::Vector{Any})
  s = x[1]
  if s isa Symbol
    x[1] = getgensym!(defined, s)
  else
    define_tup!(defined, s::Expr)
  end
end
function define_induction_variables!(defined::Dict{Symbol,Symbol}, ex::Expr) # add `i` in `for i ∈ looprange` to `defined`
  ex.head === :for || return
  loops = ex.args[1]
  if loops.head === :block
    for loop ∈ loops.args
      define1!(defined, loop.args)
    end
  else
    define1!(defined, loops.args)
  end
end

function extractargs_equal!(arguments::Vector{Symbol}, defined::Dict{Symbol,Symbol}, args::Vector{Any})
  arg1 = first(args)
  if arg1 isa Symbol
    args[1] = getgensym!(defined, arg1)
  elseif Meta.isexpr(arg1, :tuple)
    define_tup!(defined, arg1)
  end
  nothing
end
function must_add_sym(defined::Dict{Symbol,Symbol}, arg::Symbol, mod)
  ((arg ∉ keys(defined)) && arg ∉ (:nothing, :(+), :(*), :(-), :(/), :(÷), :(<<), :(>>), :(>>>), :zero, :one)) && !Base.isdefined(mod, arg)
end
function get_sym!(defined::Dict{Symbol,Symbol}, arguments::Vector{Symbol}, arg::Symbol, mod)
  if must_add_sym(defined, arg, mod)
    # @show getgensym!(defined, sym)
    # @assert false
    push!(arguments, arg)
    getgensym!(defined, arg)
  else
    get(defined, arg, arg)
  end
end
function extractargs!(arguments::Vector{Symbol}, defined::Dict{Symbol,Symbol}, expr::Expr, mod)
  define_induction_variables!(defined, expr)
  head = expr.head
  args = expr.args
  startind = 1
  if head === :call
    startind = 2
  elseif head === :(=)
    extractargs_equal!(arguments, defined, args)
  elseif head ∈ (:inbounds, :loopinfo)#, :(->))
    return
  elseif head === :(.)
    arg1 = args[1]
    if arg1 isa Symbol
      args[1] = get_sym!(defined, arguments, arg1, mod)
    else
      extractargs!(arguments, defined, arg1, mod)
    end
  elseif head === :(->)
    td = copy(defined)
    define1!(td, args)
    extractargs!(arguments, td, args[1], mod)
    extractargs!(arguments, td, args[2], mod)
    return
  elseif (head === :local) || (head === :global)
    for (i,arg) in enumerate(args)
      if Meta.isexpr(arg, :(=))
        extractargs_equal!(arguments, defined, arg.args)
        args = arg.args
        startind = 2
      else
        args[i] = getgensym!(defined, arg)
        return
      end
    end
  elseif head === :kw
    return
  end
  for i ∈ startind:length(args)
    argᵢ = args[i]
    (head === :ref && ((argᵢ === :end) || (argᵢ === :begin))) && continue
    if argᵢ isa Symbol
      args[i] = get_sym!(defined, arguments, argᵢ, mod)
    elseif argᵢ isa Expr
      extractargs!(arguments, defined, argᵢ, mod)
    else
      extractargs!(arguments, defined, argᵢ, mod)
    end
  end
  return
end

struct NoLoop end
Base.iterate(::NoLoop) = (NoLoop(), NoLoop())
Base.iterate(::NoLoop, ::NoLoop) = nothing
@inline splitloop(x) = NoLoop(), x, CombineIndices()
struct CombineIndices end
@inline splitloop(x::AbstractUnitRange) = NoLoop(), x, CombineIndices()
@inline function splitloop(x::CartesianIndices)
  axes = x.indices
  CartesianIndices(Base.front(axes)), last(axes), CombineIndices()
end
@inline function splitloop(x::AbstractArray)
  inds = eachindex(x)
  inner, outer = splitloop(inds)
  inner, outer, x
end
struct TupleIndices end
@inline function splitloop(x::Base.Iterators.ProductIterator{Tuple{T1,T2}}) where {T1,T2}
  iters = x.iterators
  iters[1], iters[2], TupleIndices()
end
@inline function splitloop(x::Base.Iterators.ProductIterator{<:Tuple{Vararg{Any,N}}}) where {N}
  iters = x.iterators
  Base.front(iters), iters[N], TupleIndices()
end
combine(::CombineIndices, ::NoLoop, x) = x
combine(::CombineIndices, I::CartesianIndex, j) = CartesianIndex((I.I..., j))
combine(::TupleIndices, i::Tuple, j) = (i..., j)
combine(::TupleIndices, i::Number, j) = (i, j)

Base.@propagate_inbounds combine(x::AbstractArray, I, j) = x[combine(CombineIndices(), I, j)]
Base.@propagate_inbounds combine(x::AbstractArray, ::NoLoop, j) = x[j]

static_literals!(s::Symbol) = s
function static_literals!(q::Expr)
  for (i,ex) ∈ enumerate(q.args)
    if ex isa Integer
      q.args[i] = StaticInt(ex)
    elseif ex isa Expr
      static_literals!(ex)
    end
  end
  q
end
function maybestatic!(_expr)::Expr
  _expr isa Expr || return esc(_expr)
  expr::Expr = _expr
  if expr.head === :call
    f = first(expr.args)
    if f === :length
      expr.args[1] = static_length
    elseif f === :size && length(expr.args) == 3
      i = expr.args[3]
      if i isa Integer
        expr.args[1] = size
        expr.args[3] = StaticInt(i)
      end
    else
      static_literals!(expr)
    end
  end
  esc(expr)
end
function enclose(exorig::Expr, reserve_per, minbatchsize, per::Symbol, mod)
  Meta.isexpr(exorig, :for, 2) || throw(ArgumentError("Expression invalid; should be a for loop."))
  ex = copy(exorig)
  loop_sym = Symbol("##LOOP##")
  loopstart = Symbol("##LOOPSTART##")
  loop_step = Symbol("##LOOP_STEP##")
  loop_stop = Symbol("##LOOP_STOP##")
  iter_leng = Symbol("##ITER_LENG##")
  loop_offs = Symbol("##LOOPOFFSET##")
  innerloop = Symbol("##inner##loop##")
  rcombiner = Symbol("##split##recombined##")

  # arguments = Symbol[]#loop_offs, loop_step]
  arguments = Symbol[innerloop, rcombiner]#loop_offs, loop_step]
  defined = Dict{Symbol,Symbol}(loop_offs => loop_offs, loop_step => loop_step)
  define_induction_variables!(defined, ex)
  firstloop = ex.args[1]
  if firstloop.head === :block
    secondaryloopsargs = firstloop.args[2:end]
    firstloop = firstloop.args[1]
  else
    secondaryloopsargs = Any[]
  end
  loop = firstloop.args[2]
  # @show ex loop
  firstlooprange = Expr(:call, GlobalRef(Base, :(:)), loopstart, loop_step, loop_stop)
  body = ex.args[2]
  if length(secondaryloopsargs) == 1
    body = Expr(:for, only(secondaryloopsargs), body)
  elseif length(secondaryloopsargs) > 1
    sl = Expr(:block); append!(sl.args, secondaryloopsargs)
    body = Expr(:for, sl, body)
  end
  fla1 = firstloop.args[1]
  excomb = if fla1 isa Symbol
    fla1 = getgensym!(defined, fla1)
    quote
      # for $(firstloop.args[1]) in
      for var"##outer##" in $firstlooprange, var"##inner##" in $innerloop
        $fla1 = $combine($rcombiner, var"##inner##", var"##outer##")
        $body
      end
    end
  else
    @assert fla1 isa Expr
    for i in eachindex(fla1.args)
      fla1.args[i] = getgensym!(defined, fla1.args[i])
    end
    quote
      # for $(firstloop.args[1]) in
      for var"##outer##" in $firstlooprange, var"##inner##" in $innerloop
        $fla1 = $combine($rcombiner, var"##inner##", var"##outer##")
        $body
      end
    end
  end
  if ex.args[1].head === :block
    for i ∈ 2:length(ex.args[1].args)
      extractargs!(arguments, defined, ex.args[1].args[i], mod)
    end
  end
  for i ∈ 2:length(ex.args)
    extractargs!(arguments, defined, ex.args[i], mod)
  end
  # @show ex.args[1] firstloop body
  # if length(ex.args[
  # ex = quote
  #   # for $(firstloop.args[1]) in
  #   for var"##outer##" in $firstlooprange, var"##inner##" in $innerloop
  #     $(firstloop.args[1]) = $combine($rcombiner, var"##inner##", var"##outer##")
  #     $body
  #   end
  # end
  # typexpr_incomplete is missing `funcs`
  # outerloop = Symbol("##outer##")
  q = quote
    $(esc(innerloop)), $loop_sym, $(esc(rcombiner)) = $splitloop($(maybestatic!(loop)))
    # $loop_sym = $(maybestatic!(loop))
    $iter_leng = $static_length($loop_sym)
    $loop_step = $static_step($loop_sym)
    $loop_offs = $static_first($loop_sym)
  end
  threadtup = Expr(:tuple, iter_leng)
  num_thread_expr = Expr(:call, num_threads)
  if per === :core
    num_thread_expr = Expr(:call, min, num_thread_expr, Expr(:call, num_cores))
  end
  if minbatchsize isa Integer && minbatchsize ≤ 1
    # if reserve_per ≤ 0
      push!(threadtup.args, :(min($iter_leng, $num_thread_expr)))
    # else
    #   push!(threadtup.args, :(min($iter_leng, cld($num_thread_expr, $reserve_per))), reserve_per)
    # end
  else
    il = :(div($iter_leng, $(minbatchsize isa Int ? StaticInt(minbatchsize) : esc(minbatchsize))))
    # if reserve_per ≤ 0
      push!(threadtup.args, :(min($il, $num_thread_expr)))
    # else
    #   push!(threadtup.args, :(min($il, cld($num_thread_expr, $reserve_per))), reserve_per)
    # end
  end
  closure = Symbol("##closure##")
  args = Expr(:tuple, Symbol("##LOOPOFFSET##"), Symbol("##LOOP_STEP##"))
  closureq = quote
    $closure = let
      @inline ($args, var"##SUBSTART##"::Int, var"##SUBSTOP##"::Int) -> begin
        var"##LOOPSTART##" = var"##SUBSTART##" * var"##LOOP_STEP##" + var"##LOOPOFFSET##" - var"##LOOP_STEP##"
        var"##LOOP_STOP##" = var"##SUBSTOP##" * var"##LOOP_STEP##" + var"##LOOPOFFSET##" - var"##LOOP_STEP##"
        @inbounds begin
          $excomb
        end
        nothing
      end
    end
  end
  push!(q.args, esc(closureq))
  batchcall = Expr(:call, batch, esc(closure), threadtup, Symbol("##LOOPOFFSET##"), Symbol("##LOOP_STEP##"))
  for a ∈ arguments
    push!(args.args, get(defined,a,a))
    push!(batchcall.args, esc(a))
  end
  push!(q.args, batchcall)
  quote
    if $num_threads() == 1
      let
        $(esc(exorig))
      end
    else
      let
        $q
      end
    end
  end
end

"""
    @batch for i in Iter; ...; end

Evaluate the loop on multiple threads.

    @batch minbatch=N for i in Iter; ...; end

Evaluate at least N iterations per thread. Will use at most `length(Iter) ÷ N` threads.

    @batch per=core for i in Iter; ...; end
    @batch per=thread for i in Iter; ...; end

Use at most 1 thread per physical core, or 1 thread per CPU thread, respectively.
One thread per core will mean less threads competing for the cache, while (for example) if
there are two hardware threads per physical core, then using each thread means that there
are two independent instruction streams feeding the CPU's execution units. When one of
these streams isn't enough to make the most of out of order execution, this could increase
total throughput.

Which performs better will depend on the workload, so if you're not sure it may be worth
benchmarking both.

LoopVectorization.jl currently only uses up to 1 thread per physical core. Because there
is some overhead to switching the number of threads used, `per=core` is `@batch`'s default,
so that `Polyester.@batch` and `LoopVectorization.@tturbo` work well together by default.

You can pass both `per=(core/thread)` and `minbatch=N` options at the same time, e.g.

    @batch per=thread minbatch=2000 for i in Iter; ...; end
    @batch minbatch=5000 per=core   for i in Iter; ...; end
"""
macro batch(ex)
  enclose(macroexpand(__module__, ex), 0, 1, :core, __module__)
end
function interpret_kwarg(arg, reserve_per = 0, minbatch = 1, per = :core)
  a = arg.args[1]
  v = arg.args[2]
  if a === :reserve
    @assert v ≥ 0
    reserve_per = v
  elseif a === :minbatch
    minbatch = v
  elseif a === :per
    per = v::Symbol
    @assert (per === :core) | (per === :thread)
  else
    throw(ArgumentError("kwarg $(a) not recognized."))
  end
  reserve_per, minbatch, per
end
macro batch(arg1, ex)
  reserve, minbatch, per = interpret_kwarg(arg1)
  enclose(macroexpand(__module__, ex), reserve, minbatch, per, __module__)
end
macro batch(arg1, arg2, ex)
  reserve, minbatch, per = interpret_kwarg(arg1)
  reserve, minbatch, per = interpret_kwarg(arg2, reserve, minbatch, per)
  enclose(macroexpand(__module__, ex), reserve, minbatch, per, __module__)
end
macro batch(arg1, arg2, arg3, ex)
  reserve, minbatch, per = interpret_kwarg(arg1)
  reserve, minbatch, per = interpret_kwarg(arg2, reserve, minbatch, per)
  reserve, minbatch, per = interpret_kwarg(arg2, reserve, minbatch, per)
  enclose(macroexpand(__module__, ex), reserve, minbatch, per, __module__)
end
