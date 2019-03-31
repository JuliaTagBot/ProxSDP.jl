
struct CircularVector{T}
    v::Vector{T}
    l::Int
    CircularVector{T}(l::Integer) where T = new(zeros(T, l), l)
end
function Base.getindex(V::CircularVector{T}, i::Int) where T
    return V.v[mod1(i, V.l)]
end
function Base.setindex!(V::CircularVector{T}, val::T, i::Int) where T
    V.v[mod1(i, V.l)] = val
end

# --------------------------------
mutable struct Options
    log_verbose::Bool
    log_freq::Int
    timer_verbose::Bool
    max_iter::Int
    tol_primal::Float64
    tol_dual::Float64
    tol_eig::Float64
    tol_soc::Float64

    initial_theta::Float64
    initial_beta::Float64
    min_beta::Float64
    max_beta::Float64
    initial_adapt_level::Float64
    adapt_decay::Float64 # Rate the adaptivity decreases over time
    convergence_window::Int

    convergence_check::Int

    residual_relative_diff::Float64

    max_linsearch_steps::Int

    full_eig_decomp::Bool
    max_target_rank_krylov_eigs::Int
    min_size_krylov_eigs::Int

    function Options()
        opt = new()

        opt.log_verbose = false
        opt.log_freq = 100
        opt.timer_verbose = false

        opt.max_iter = Int(1e+5)

        opt.tol_primal = 1e-4
        opt.tol_dual = 1e-4
        opt.tol_eig = 1e-6
        opt.tol_soc = 1e-6

        opt.initial_theta = 1.0
        opt.initial_beta = 1.0
        opt.min_beta = 1e-2
        opt.max_beta = 1e+8
        opt.initial_adapt_level = 0.9
        opt.adapt_decay = 0.9
        opt.convergence_window = 100

        opt.convergence_check = 50

        opt.residual_relative_diff = 100.0

        opt.max_linsearch_steps = 1000

        opt.full_eig_decomp = false

        opt.max_target_rank_krylov_eigs = 16
        opt.min_size_krylov_eigs = 100

        return opt
    end
end
function Options(args)
    options = Options()
    parse_args!(options, args)
    return options
end
function parse_args!(options, args)
    for i in args
        parse_arg!(options, i)
    end
    return nothing
end
function parse_arg!(options::Options, arg)
    fields = fieldnames(Options)
    name = arg[1]
    value = arg[2]
    if name in fields
        setfield!(options, name, value)
    end
    return nothing
end

mutable struct AffineSets
    n::Int  # Size of primal variables
    p::Int  # Number of linear equalities
    m::Int  # Number of linear inequalities
    extra::Int  # Number of adition linear equalities (for disjoint cones)
    A::SparseMatrixCSC{Float64,Int64}#AbstractMatrix{T}
    G::SparseMatrixCSC{Float64,Int64}#AbstractMatrix{T}
    b::Vector{Float64}
    h::Vector{Float64}
    c::Vector{Float64}
end

mutable struct SDPSet
    vec_i::Vector{Int}
    mat_i::Vector{Int}
    tri_len::Int
    sq_len::Int
    sq_side::Int
end

mutable struct SOCSet
    idx::Vector{Int}
    len::Int
end

mutable struct ConicSets
    sdpcone::Vector{SDPSet}
    socone::Vector{SOCSet}
end

struct CPResult
    status::Int
    primal::Vector{Float64}
    dual::Vector{Float64}
    slack::Vector{Float64}
    primal_residual::Float64
    dual_residual::Float64
    objval::Float64
    dual_objval::Float64
    gap::Float64
    time::Float64
end

mutable struct PrimalDual
    x::Vector{Float64}
    x_old::Vector{Float64}

    y::Vector{Float64}
    y_old::Vector{Float64}
    y_aux::Vector{Float64}

    PrimalDual(aff) = new(
        zeros(aff.n), zeros(aff.n), zeros(aff.m+aff.p), zeros(aff.m+aff.p), zeros(aff.m+aff.p)
    )
end

const ViewVector = SubArray#{Float64, 1, Vector{Float64}, Tuple{UnitRange{Int}}, true}
const ViewScalar = SubArray#{Float64, 1, Vector{Float64}, Tuple{Int}, true}

mutable struct AuxiliaryData
    m::Vector{Symmetric{Float64,Matrix{Float64}}}
    Mty::Vector{Float64}
    Mty_old::Vector{Float64}
    Mty_aux::Vector{Float64}
    Mx::Vector{Float64}
    Mx_old::Vector{Float64}
    y_half::Vector{Float64}
    y_temp::Vector{Float64}
    MtMx::Vector{Float64}
    MtMx_old::Vector{Float64}
    Mtrhs::Vector{Float64}
    soc_v::Vector{ViewVector}
    soc_s::Vector{ViewScalar}
    function AuxiliaryData(aff::AffineSets, cones::ConicSets) 
        new([Symmetric(zeros(sdp.sq_side, sdp.sq_side), :L) for sdp in cones.sdpcone], zeros(aff.n), zeros(aff.n),
        zeros(aff.n), zeros(aff.p+aff.m), zeros(aff.p+aff.m), zeros(aff.p+aff.m), 
        zeros(aff.p+aff.m), zeros(aff.n), zeros(aff.n), zeros(aff.n),
        ViewVector[], ViewScalar[]
    )
    end
end

mutable struct Matrices
    M::SparseMatrixCSC{Float64,Int64}
    Mt::SparseMatrixCSC{Float64,Int64}
    c::Vector{Float64}
    Matrices(M, Mt, c) = new(M, Mt, c)
end

mutable struct Params

    target_rank::Vector{Int}
    rank_update::Int
    update_cont::Int
    min_eig::Vector{Float64}

    iter::Int
    converged::Bool
    iteration::Int

    primal_step::Float64
    primal_step_old::Float64
    dual_step::Float64

    theta::Float64
    beta::Float64
    adapt_level::Float64

    window::Int

    # constants
    time0::Float64
    norm_c::Float64
    norm_rhs::Float64
    sqrt2::Float64

    Params() = new()
end