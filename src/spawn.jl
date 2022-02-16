struct SpawnClosure{F, A}
end
function (b::SpawnClosure{F,A})(p::Ptr{UInt}) where {F,A}
  (_, args) = ThreadingUtilities.load(p, A, 2*sizeof(UInt))
  F.instance(args...)
  nothing
end
# task pointers contain...
# state, fptr, misc...
# fptr = unsafe_load(ptr, 2)
# fptr(ptr)

@inline function setup_spawn!(p::Ptr{UInt}, fptr::Ptr{Cvoid}, argtup)
  offset = ThreadingUtilities.store!(p, fptr, sizeof(UInt))
  offset = ThreadingUtilities.store!(p, argtup, offset)
  nothing
end

@generated function spawn_closure(::F, args::A) where {F,A}
  :(@cfunction($(F.instance), Cvoid, (Ptr{UInt},)))
end

"""
  @spawnf t foo

```julia
t = Polyester.request_threads(7)
t = Polyester.@spawnf t foo1(...)
t = Polyester.@spawnf t foo2(...)
t = Polyester.@spawnf t foo3(...)
t = Polyester.@spawnf t foo4(...)
t = Polyester.@spawnf t foo5(...)
t = Polyester.@spawnf t foo6(...)
t = Polyester.@spawnf t foo7(...)
foo8(...)
wait(t)

"""
macro spawnf(tex, ex)
  @assert tex isa Symbol
  f = GlobalRef(__module__, ex.args[1])
  args = @view(ex.args[2:end])
  Nargs = length(args)
  argtup = Expr(:tuple); resize!(argtup.args, Nargs)
  for i in 1:Nargs
    argtup.args[i] = args[i]
  end
  argsgs = gensym(:args)
  fptrgs = gensym(:fptr)
  tgs = gensym(:t)
  tid = gensym(:tid)
  q = quote
    # p is the taskpointer
    $argsgs = $argtup
    $fptrgs = $spawn_closure($f, $argsgs)
    $tid, $tgs = $popfirst($tex)
    $(ThreadingUtilities.launch)($tid, $fptrgs, $argsgs) do p, fptr, argtup
      $setup_spawn!(p, fptr, argtup)
    end
    $tgs
  end
  esc(q)
end


#=
"""
  @spawnf foo

```julia
t = Polyester.@spawnf foo(...)
# run more code here
# later, to synchronize and free the thread
Polyester.wait(t)

If you would like to get a result of type `T`, write
`foo!(::Base.RefValue{T}, args...)
and then
```julia
r = Ref{T}()
t = @spawn foo!(r, args...)
# run code
Polyester.wait(t)
```
"""
macro spawnf(ex)
  f = ex.args[1]
  args = @view(ex.args[2:end])
  Nargs = length(args)
  argtup = Expr(:tuple); resize!(argtup.args, Nargs)
  for i in 1:Nargs
    argtup.args[i] = args[i]
  end
  closure = gensym(:closure)
  
  quote

  end
  
end
=#
