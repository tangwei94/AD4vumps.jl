function mps_update(AC::MPSTensor, C::MPSBondTensor)
    UAC_l, PAC_l = leftorth(AC; alg = QRpos())
    UC_l, PC_l = leftorth(C; alg = QRpos())

    PAC_r, UAC_r = rightorth(permute(AC, ((1,), (2, 3))); alg = LQpos())
    PC_r, UC_r = rightorth(C; alg=LQpos())

    AL = UAC_l * UC_l'
    AR = permute(UC_r' * UAC_r, ((1, 2), (3,)))

    # check AC - AL * C and AC - C * AR
    conv_meas = ignore_derivatives() do
        ϵL = norm(PAC_l - PC_l) 
        ϵR = norm(PAC_r - PC_r)
        conv_meas = max(ϵL, ϵR)
        return conv_meas
    end

    return AL, AR, conv_meas
end

function vumps_update(AL::MPSTensor, AR::MPSTensor, T::MPOTensor)

    TM_L = MPSMPOMPSTransferMatrix(AL, T, AL)
    TM_R = MPSMPOMPSTransferMatrix(AR, T, AR)

    EL = left_env(TM_L)
    ER = right_env(TM_R)

    # AC map
    AC_map = ACMap(EL, T, ER)
    AC = fixed_point(AC_map)

    # C map
    C_map = MPSMPSTransferMatrix(EL', ER)
    C = left_env(C_map) 

    return AC, C
end

function vumps(T::MPOTensor; A::MPSTensor, maxiter=500, tol=1e-12, verbosity=1)
    AL, AR, AC, C = ignore_derivatives() do
        sp = domain(A)[1]
        C = TensorMap(rand, ComplexF64, sp, sp)
        AL, _ = left_canonical_QR(A)
        AR, _ = right_canonical_QR(A)
        AC, C = vumps_update(AL, AR, T)
        return AL, AR, AC, C
    end

    conv_meas = 999
    ix = 0
    while conv_meas > tol && ix < maxiter
        ix += 1
        AC, C = vumps_update(AL, AR, T)
        AL, AR, conv_meas = mps_update(AC, C)
        verbosity > 0 && print(ix, ' ', conv_meas, "     \r")
    end
    verbosity > 0 && print("\n")
    return AL, AR
end

# https://github.com/QuantumKitHub/PEPSKit.jl/blob/a6afe158c3cb375c75b2f119a2481882bafe866e/src/algorithms/peps_opt.jl#L116-L173
function ChainRulesCore.rrule(::typeof(vumps), T::MPOTensor; maxiter=500, tol=1e-12, kwargs...)
    AL, AR = vumps(T; maxiter=maxiter, tol=tol, kwargs...)

    function vumps_pushback_arnoldi(∂ALAR)
        (∂AL, ∂AR) = ∂ALAR
        _, vumps_iteration_vjp = pullback(gauge_fixed_vumps_iteration, AL, AR, T)

        function vjp_ALAR_ALAR(X)
            res = vumps_iteration_vjp((X[1], X[2]))
            return [res[1], res[2]]
        end
        vjp_ALAR_T(X) = vumps_iteration_vjp((X[1], X[2]))[3]
        X1 = vjp_ALAR_ALAR([∂AL, ∂AR]) 
        Y1 = [X1[1], X1[2], 1]
        @show inner(Y1, Y1)
        function f_map(Y)
            Yx = vjp_ALAR_ALAR([Y[1], Y[2]]) 
            return [Yx[1] + X1[1], Yx[2] + X1[2], Y[3]]
        end
        #KrylovKit.VectorInterface.scalartype(a::Vector{Any}) = KrylovKit.VectorInterface.scalartype(a[1])
        vals, vecs, info = eigsolve(f_map, Y1, 2, :LM)
        Xsum = [vecs[1][1], vecs[1][2]]
        (!isnothing(∂AL)) && (Xsum[1] += ∂AL)
        (!isnothing(∂AR)) && (Xsum[2] += ∂AR)
        ∂T = vjp_ALAR_T(Xsum)
        return NoTangent(), ∂T # FIXME. does not work
    end

    function vumps_pushback_linsolve(∂ALAR)
        (∂AL, ∂AR) = ∂ALAR
        _, vumps_iteration_vjp = pullback(gauge_fixed_vumps_iteration, AL, AR, T)
        
        function vjp_ALAR_ALAR(X)
            res = vumps_iteration_vjp((X[1], X[2]))
            return [res[1], res[2]]
        end
        vjp_ALAR_T(X) = vumps_iteration_vjp((X[1], X[2]))[3]
        X1 = vjp_ALAR_ALAR([∂AL, ∂AR]) 
        f_map(X) = X - vjp_ALAR_ALAR(X)
        Xsum, info = linsolve(f_map, X1, X1; tol= sqrt(tol)) # tol cannot be too small
        println("vumps_pushback: linsolve info: ", info)
        (!isnothing(∂AL)) && (Xsum[1] += ∂AL)
        (!isnothing(∂AR)) && (Xsum[2] += ∂AR)
        ∂T = vjp_ALAR_T(Xsum)
        
        return NoTangent(), ∂T
    end

    function vumps_pushback_geometric_series(∂ALAR)
        (∂AL, ∂AR) = ∂ALAR
        _, vumps_iteration_vjp = pullback(gauge_fixed_vumps_iteration, AL, AR, T)
        
        function vjp_ALAR_ALAR(X)
            res = vumps_iteration_vjp((X[1], X[2]))
            return [res[1], res[2]]
        end
        vjp_ALAR_T(X) = vumps_iteration_vjp((X[1], X[2]))[3]
        Xj = vjp_ALAR_ALAR([∂AL, ∂AR])
        Xsum = Xj
        ϵ = Inf
        for ix in 1:maxiter
            Xj = vjp_ALAR_ALAR(Xj)
            Xsum += Xj
            ϵ = norm(Xj)
            println("INFO vumps_pushback: $(ix) ϵ = ", ϵ)
            (ϵ < sqrt(tol)) && break # ϵ normally does not go to exact 0. so tol cannot be too small
        end
        #Xsum1, info = linsolve(vjp_ALAR_ALAR, X1, X1, 1, -1)
        #@show Xsum - Xsum1 |> norm
        (!isnothing(∂AL)) && (Xsum[1] += ∂AL)
        (!isnothing(∂AR)) && (Xsum[2] += ∂AR)
        ∂T = vjp_ALAR_T(Xsum)
        
        return NoTangent(), ∂T
    end
    return (AL, AR), vumps_pushback_linsolve
end

