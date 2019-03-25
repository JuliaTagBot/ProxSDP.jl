
function convergedrank(p::Params, cones::ConicSets, opt::Options)
    for (idx, sdp) in enumerate(cones.sdpcone)
        if !(p.min_eig[idx] < opt.tol_psd || p.target_rank[idx] > opt.max_target_rank_krylov_eigs || sdp.sq_side < opt.min_size_krylov_eigs)
            return false
        end
    end
    return true
end

function compute_residual!(pair::PrimalDual, a::AuxiliaryData, primal_residual::CircularVector{Float64}, dual_residual::CircularVector{Float64}, comb_residual::CircularVector{Float64}, mat::Matrices, p::Params, aff::AffineSets)

    diff = (1. / p.primal_step) * (pair.x - pair.x_old) + (a.Mty - a.Mty_old)
    primal_residual[p.iter] = norm(diff, Inf) / max(1. + p.norm_c, 1e-4)

    diff = (1. / p.dual_step) * (pair.y - pair.y_old) + (a.Mx - a.Mx_old)
    dual_residual[p.iter] = norm(diff, Inf) / max(1. + p.norm_rhs, 1e-4)

    # Compute combined residual
    comb_residual[p.iter] = primal_residual[p.iter] + dual_residual[p.iter]

    # Keep track of previous iterates
    copyto!(pair.x_old, pair.x)
    copyto!(pair.y_old, pair.y)
    copyto!(a.Mty_old, a.Mty)
    copyto!(a.Mx_old, a.Mx)

    return nothing
end

function soc_gap(v::ViewVector, s::ViewScalar)
    return norm(v) - s[]
end

function soc_convergence(a::AuxiliaryData, cones::ConicSets, pair::PrimalDual, opt::Options, p::Params)
    for (idx, soc) in enumerate(cones.socone)
        if soc_gap(a.soc_v[idx], a.soc_s[idx]) >= opt.tol_soc
            return false
        end
    end
    return true
end