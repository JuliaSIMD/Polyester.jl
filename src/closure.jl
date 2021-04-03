
struct Expression{H,A} end
totype(s::Symbol) = QuoteNode(s)
totype(s::Number) = s
totype(::Nothing) = nothing


totype!(funcs::Expr, arguments::Vector, defined::Set, sym) = sym
function totype!(funcs::Expr, arguments::Vector, defined::Set, sym::Symbol)
    if sym ∉ defined
        push!(defined, sym)
        push!(arguments, sym)
    end
    QuoteNode(sym)
end
# function totype(expr::Expr)::Expr
#     t = Expr(:tuple)
#     ex = Expr(:curly, :Expression, QuoteNode(expr.head), t)
#     for a ∈ expr.args
#         push!(t.args, totype(a))
#     end
#     Expr(:call, ex)
# end

function define_induction_variables!(defined::Set, ex::Expr) # add `i` in `for i ∈ looprange` to `defined`
    ex.head === :for || return
    loops = ex.args[1]
    if loops.head === :block
        for loop ∈ loops.args
            push!(defined, loop.args[1])
        end
    else
        push!(defined, loops.args[1])
    end
end

maybecopy(s::Symbol) = s
maybecopy(ex::Expr) = copy(ex)
function totype!(funcs::Expr, arguments::Vector, defined::Set, expr::Expr)::Expr
    define_induction_variables!(defined, expr)
    head = expr.head
    args = expr.args
    updateind = findfirst(Base.Fix2(===, head), (:(+=), :(-=), :(*=), :(/=)))
    if updateind !== nothing
        args[2] = Expr(:call, (:(+), :(-), :(*), :(/))[updateind], maybecopy(args[1]), args[2])
        head = :(=)
    end
    t = Expr(:tuple)
    ex = Expr(:curly, :Expression, QuoteNode(head), t)
    if head === :call
        push!(funcs.args, esc(popfirst!(args)))
    elseif head === :(=)
        args[1] isa Symbol && push!(defined, args[1])
    end
    for a ∈ args
        push!(t.args, totype!(funcs, arguments, defined, a))
    end
    Expr(:call, ex)
end

function _substitute_functions(@nospecialize(_::Expression{H,A}), k::Int) where {H,A}
    t = Expr(:tuple)
    ex = Expr(:curly, :Expression, QuoteNode(H), t)
    if H === :call
        push!(t.args, Expr(:call, GlobalRef(Core, :getfield), :funcs, (k+=1), false))
    end
    for a ∈ A
        if a isa Expression
            exa, k = _substitute_functions(a, k)
            push!(t.args, exa)
        else
            push!(t.args, totype(a))
        end
    end
    Expr(:block, Expr(:meta,:inline), Expr(:call, ex)), k
end

@generated function substitute_functions(::Expression{H,A}, funcs::Tuple{Vararg{Any,K}}) where {H,A,K}
    ex, k = _substitute_functions(Expression{H,A}(),0)
    @assert k == K
    ex
end

toexpr(x) = x
function (toexpr(@nospecialize(_::Expression{H,A}))::Expr) where {H,A}
    ex = Expr(H)
    for a ∈ A
        push!(ex.args, toexpr(a))
    end
    ex
end

struct Closure{E,A} <: Function end

@generated function (::Closure{E,A})(args::Tuple{Vararg{Any,K}}, var"##SUBSTART##"::Int, var"##SUBSTOP##"::Int) where {K,A,E}
    q = Expr(:block)
    gf = GlobalRef(Core, :getfield)
    for k ∈ 1:K
        push!(q.args, Expr(:(=), A[k], Expr(:call, gf, :args, k, false)))
    end
    q = quote
        @inbounds begin
            $q
            var"##LOOPSTART##" = var"##SUBSTART##" * var"##LOOP_STEP##" - var"##LOOPOFFSET##"
            var"##LOOP_STOP##" = var"##SUBSTOP##" * var"##LOOP_STEP##" - var"##LOOPOFFSET##"
            $(toexpr(E))
        end
        nothing
    end
    # Core.println(q)
    q
end

# @generated function (::Closure{E,S,A})(p::Ptr{UInt}) where {E,S,A}
#     q = quote
#         offset, args = ThreadingUtilities.load(p, A, 2*sizeof(UInt))
#     end
#     gf = GlobalRef(Core,:getfield)
#     for (i,s) ∈ enumerate(S)
#         push!(q.args, Expr(:(=), s, Expr(:call, gf, :args, i, false)))
#     end
#     push!(q.args, :(@inbounds $(toexpr(E()))))
#     push!(q.args, nothing)
#     q
# end
# @generated function Base.pointer(::Closure{E,S,A}) where {E,S,A}
#     f = Closure{E,S,A}()
#     precompile(f, (Ptr{UInt},))
#     quote
#         $(Expr(:meta,:inline))
#         @cfunction($f, Cvoid, (Ptr{UInt},))
#     end
# end
# function enclose!(p::Ptr{UInt}, args::A, ::Val{E}, ::Val{S}) where {E,S,A}
#     offset = ThreadingUtilities.store!(p, pointer(Closure{E,S,A}()), sizeof(UInt))
#     offset = ThreadingUtilities.store!(p, args, S)
# end

function enclose(exorig::Expr, reserve_per = 0)
    Meta.isexpr(exorig, :for, 2) || throw(ArgumentError("Expression invalid; should be a for loop."))
    ex = copy(exorig)
    loop_sym = Symbol("##LOOP##")
    loopstart = Symbol("##LOOPSTART##")
    loop_step = Symbol("##LOOP_STEP##")
    loop_stop = Symbol("##LOOP_STOP##")
    iter_leng = Symbol("##ITER_LENG##")
    loop_offs = Symbol("##LOOPOFFSET##")

    funcs = Expr(:tuple)
    arguments = Symbol[loop_offs, loop_step]
    defined = Set(arguments);
    push!(defined, loop_stop, loopstart)

    firstloop = ex.args[1]
    if firstloop.head === :block
        firstloop = firstloop.args[1]
    end
    loop = firstloop.args[2]
    firstloop.args[2] = :($loopstart:$loop_step:$loop_stop)
    # typexpr_incomplete is missing `funcs`
    typexpr_incomplete = totype!(funcs, arguments, defined, ex)
    typexpr = Expr(:call, GlobalRef(CheapThreads, :substitute_functions), typexpr_incomplete, funcs)

    argsyms = Expr(:tuple)
    threadtup = Expr(:tuple, iter_leng)
    if reserve_per ≤ 0
        push!(threadtup.args, :(min($iter_leng, CheapThreads.num_threads())))
    else
        push!(threadtup.args, :(min($iter_leng, cld(CheapThreads.num_threads(), $reserve_per))), reserve_per)
    end
    closure = Expr(:call, Expr(:curly, GlobalRef(CheapThreads, :Closure), typexpr, argsyms))
    batchcall = Expr(:call, GlobalRef(CheapThreads, :batch), closure, threadtup)
    for a ∈ arguments
        push!(argsyms.args, QuoteNode(a))
        push!(batchcall.args, esc(a))
    end
    
    # loop_ex = (ex.args[1])::Expr
    # m = __module__
    q = quote
        $loop_sym = $(esc(loop))
        $iter_leng = static_length($loop_sym)
        $(esc(loop_step)) = CheapThreads.static_step($loop_sym)
        $(esc(loop_offs)) = CheapThreads.static_first($loop_sym) - $(Static.One())
        typesinserted = $typexpr
        # @show typesinserted
        $batchcall
    end
    quote
        if CheapThreads.num_threads() == 1
            $(esc(exorig))
        else
            $q
        end
    end
end

macro batch(ex)
    enclose(ex)
end
macro batch(reserve_per, ex)
    enclose(ex, reserve_per)
end
# macro batch(kwarg, ex)
#     enclose(ex, kwarg)
# end

