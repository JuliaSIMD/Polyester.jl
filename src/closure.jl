
struct Expression{H,A} end
totype(s::Symbol) = QuoteNode(s)
totype(s::Number) = s
totype(::Nothing) = nothing
totype(::Val{T}) where {T} = Val{T}()

totype!(funcs::Expr, arguments::Vector, defined::Set, q::Expr, sym) = sym
function totype!(funcs::Expr, arguments::Vector, defined::Set, q::Expr, sym::Symbol)
    if (sym ∉ defined) && sym ≢ :nothing
        push!(defined, sym)
        push!(arguments, sym)
    end
    QuoteNode(sym)
end
function define_tup!(defined::Set, ex::Expr)
    for a ∈ ex.args
        if a isa Symbol
            push!(defined, a)
        else
            define_tup!(defined, a)
        end
    end
end
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
depends_on_defined(defined::Set, f)::Bool = false
depends_on_defined(defined::Set, f::Function)::Bool = f === Threads.threadid
depends_on_defined(defined::Set, f::QuoteNode) = f.value === :threadid
depends_on_defined(defined::Set, f::Symbol)::Bool = (f ∈ defined) || (f === :threadid)
function depends_on_defined(defined::Set, f::Expr)::Bool
    for a ∈ f.args
        depends_on_defined(defined, a) && return true
    end
    false
end
function totype!(funcs::Expr, arguments::Vector, defined::Set, q::Expr, expr::Expr)
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
        f = popfirst!(args)
        if length(args) > 0 || depends_on_defined(defined, f)
            push!(funcs.args, esc(f))
        else
            fgen = gensym(:f)
            push!(q.args, Expr(:(=), esc(fgen), Expr(:call, f)))
            return esc(fgen)
        end
    elseif head === :(=)
        arg1 = first(args)
        if arg1 isa Symbol
            push!(defined, arg1)
        elseif Meta.isexpr(arg1, :tuple)
            define_tup!(defined, arg1)
        end
    elseif head ∈ (:inbounds, :loopinfo)
        for arg ∈ args
            if arg isa Bool
                push!(t.args, arg)
            else
                push!(t.args, QuoteNode(arg))
            end
        end
        return Expr(:call, ex)
    elseif head === :(.)
        push!(t.args, totype!(funcs, arguments, defined, q, args[1]))
        push!(t.args, args[2])
        return Expr(:call, ex)
    end
    for a ∈ args
        push!(t.args, totype!(funcs, arguments, defined, q, a))
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
    Expr(:call, ex), k
end

@generated function substitute_functions(::Expression{H,A}, funcs::Tuple{Vararg{Any,K}}) where {H,A,K}
    ex, k = _substitute_functions(Expression{H,A}(),0)
    @assert k == K
    Expr(:block, Expr(:meta,:inline), ex)
end

toexpr(x) = x
function (toexpr(@nospecialize(_::Expression{H,A}))::Expr) where {H,A}
    ex = Expr(H)
    if H === :(.)
        push!(ex.args, toexpr(A[1]))
        push!(ex.args, QuoteNode(A[2]))
    else
        for a ∈ A
            push!(ex.args, toexpr(a))
        end
    end
    ex
end

struct Closure{E,A} <: Function end

@generated function (::Closure{var"##E##",var"##A##"})(var"##args##"::Tuple{Vararg{Any,var"##K##"}}, var"##SUBSTART##"::Int, var"##SUBSTOP##"::Int) where {var"##K##",var"##A##",var"##E##"}
    q = Expr(:block)
    gf = GlobalRef(Core, :getfield)
    for k ∈ 1:var"##K##"
        push!(q.args, Expr(:(=), var"##A##"[k], Expr(:call, gf, Symbol("##args##"), k, false)))
    end
    quote
        @inbounds begin
            $q
            var"##LOOPSTART##" = var"##SUBSTART##" * var"##LOOP_STEP##" - var"##LOOPOFFSET##"
            var"##LOOP_STOP##" = var"##SUBSTOP##" * var"##LOOP_STEP##" - var"##LOOPOFFSET##"
            $(toexpr(var"##E##"))
        end
        nothing
    end
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
    q = quote
        $loop_sym = $(esc(loop))
        $iter_leng = static_length($loop_sym)
        $(esc(loop_step)) = CheapThreads.static_step($loop_sym)
        $(esc(loop_offs)) = CheapThreads.static_first($loop_sym) - $(Static.One())
    end
    typexpr_incomplete = totype!(funcs, arguments, defined, q, ex)
    typexpr = Expr(:call, GlobalRef(CheapThreads, :substitute_functions), typexpr_incomplete, funcs)
    
    argsyms = Expr(:tuple)
    threadtup = Expr(:tuple, iter_leng)
    if reserve_per ≤ 0
        push!(threadtup.args, :(min($iter_leng, CheapThreads.num_threads())))
    else
        push!(threadtup.args, :(min($iter_leng, cld(CheapThreads.num_threads(), $reserve_per))), reserve_per)
    end
    closure = Expr(:call, Expr(:curly, GlobalRef(CheapThreads, :Closure), Symbol("##type#inserted##"), argsyms))
    batchcall = Expr(:call, GlobalRef(CheapThreads, :batch), closure, threadtup)
    for a ∈ arguments
        push!(argsyms.args, QuoteNode(a))
        push!(batchcall.args, esc(a))
    end
    push!(q.args, :(var"##type#inserted##" = $typexpr))
    push!(q.args, batchcall)
    quote
        if CheapThreads.num_threads() == 1
            $(esc(exorig))
        else
            $q
        end
    end
end

macro batch(ex)
    enclose(macroexpand(__module__, ex))
end
macro batch(reserve_per, ex)
    enclose(macroexpand(__module__, ex), reserve_per)
end

