@testset "test AD for mps_update" for ix in 1:10
    sp1 = ℂ^4;
    sp2 = ℂ^2;

    AC = TensorMap(rand, ComplexF64, sp1*sp2, sp1);
    C = TensorMap(rand, ComplexF64, sp1, sp1);
    QAC = TensorMap(rand, ComplexF64, sp1*sp2, sp1);

    function _F1(C1)
        AL, AR, _ = mps_update(AC, C1)
        return norm(tr(QAC' * AL)) + norm(tr(QAC * AR'))
    end
    function _F2(AC1)
        AL, AR, _ = mps_update(AC1, C)
        return norm(tr(QAC' * AL)) + norm(tr(QAC * AR'))
    end
  
    test_ADgrad(_F1, C)
    test_ADgrad(_F2, AC)
end

@testset "test AD for vumps_update" for ix in 1:10
    sp1 = ℂ^4;
    sp2 = ℂ^2;

    AC0 = TensorMap(rand, ComplexF64, sp1*sp2, sp1);
    C0 = TensorMap(rand, ComplexF64, sp1, sp1);
    AL, AR, _ = mps_update(AC0, C0);
    QAC = TensorMap(rand, ComplexF64, sp1*sp2, sp1);
    QC = TensorMap(rand, ComplexF64, sp1, sp1);

    βc = asinh(1) / 2
    T = tensor_square_ising(βc)
    
    function _F1(AL1)
        AC, C = vumps_update(AL1, AR, T; AC_init=AC0, C_init=C0)
        return norm(tr(QAC' * AC)) / norm(AC) + norm(tr(C)) / norm(C)
    end
    function _F2(AR1)
        AC, C = vumps_update(AL, AR1, T)
        return norm(tr(QAC' * AC)) / norm(AC) + norm(tr(C)) / norm(C)
    end
    function _F3(T1)
        AC, C = vumps_update(AL, AR, T1; AC_init=AC0)
        return norm(tr(QAC' * AC)) / norm(AC) + norm(tr(C)) / norm(C)
    end
  
    test_ADgrad(_F1, AL; α=1e-4, tol=1e-4)
    test_ADgrad(_F2, AR; α=1e-4, tol=1e-4)
    test_ADgrad(_F3, T; α=1e-4, tol=1e-4)
end

@testset "test AD for one vumps step" for ix in 1:10

    sp1 = ℂ^4;
    sp2 = ℂ^2;

    AC0 = TensorMap(rand, ComplexF64, sp1*sp2, sp1);
    C0 = TensorMap(rand, ComplexF64, sp1, sp1);
    AL, AR, _ = mps_update(AC0, C0);

    function _F(T; AL1=AL, AR1=AR)
        AC1, C1 = vumps_update(AL1, AR1, T)
        AL2, AR2, _ = mps_update(AC1, C1)

        @tensor vl[-1] := AL2[1 -1; 1]
        return norm(vl) / norm(AL2)
    end

    T = tensor_square_ising(asinh(1) / 2)
    test_ADgrad(_F, T)
end

@testset "test ad for vumps (partial test)" for ix in 1:10
    T = tensor_square_ising(asinh(1) / 2)
    A = TensorMap(rand, ComplexF64, ℂ^4*ℂ^2, ℂ^4) 
    AL, AR, AC, C = vumps(A, T)
    
    function _F1(T)
        AL1, AR1, AC1, C1 = vumps_for_ad(T; AL=AL, AR=AR, AC=AC, C=C)
        @tensor vl[-1] := AL1[1 -1; 1]
        return norm(vl) / norm(AL1)
    end
    ad1 = _F1'(T)
    ad2 = _F1'(T)
    @show norm(ad1), norm(ad2)
    @test norm(ad1 - ad2) < 1e-8
   
    #function _F(T)
    #    AL, AR, AC, C = vumps(A, T)
    #    AL1, AR1, AC1, C1 = vumps_for_ad(T; AL=AL, AR=AR, AC=AC, C=C)
    #    @tensor vl[-1] := AL1[1 -1; 1]
    #    return norm(vl) / norm(AL1)
    #end
    #ad1 = _F'(T)
    #ad2 = _F'(T)
    #@show norm(ad1), norm(ad2)
    #@test norm(ad1 - ad2) < 1e-8

    #for ix in []
    #    sX = random_real_symmetric_tensor(2)
    #    test_ADgrad(_F, T; α=1e-4, tol=1e-4, sX=sX, num=1)
    #end
end

#@testset "test ad for vumps" for ix in 1:10
#    T = tensor_square_ising(asinh(1) / 2)
#    A = TensorMap(rand, ComplexF64, ℂ^4*ℂ^2, ℂ^4) 
#    O = random_real_symmetric_tensor(2)
#    AL, AR, AC, C = vumps(A, T)
#    
#    function _F1(T)
#        AL1, AR1, AC1, C1 = vumps_for_ad(T; AL=AL, AR=AR, AC=AC, C=C)
#        TM = MPSMPOMPSTransferMatrix(AL1, T, AL1, false)
#        EL = left_env(TM)
#        ER = right_env(TM)
#
#        @tensor a = EL[4; 1 2] * AL1[1 3; 6] * O[2 5; 3 8] * conj(AL1[4 5; 7]) * ER[6 8; 7]
#        @tensor b = EL[4; 1 2] * AL1[1 3; 6] * T[2 5; 3 8] * conj(AL1[4 5; 7]) * ER[6 8; 7]
#
#        return real(a/b)
#    end
#    ad1 = _F1'(T)
#    ad2 = _F1'(T)
#    @show norm(ad1), norm(ad2)
#    @test norm(ad1 - ad2) < 1e-8
#   
#    function _F(T)
#        AL, AR, AC, C = vumps(A, T)
#        AL1, AR1, AC1, C1 = vumps_for_ad(T; AL=AL, AR=AR, AC=AC, C=C, maxiter=1)
#        TM = MPSMPOMPSTransferMatrix(AL1, T, AL1, false)
#        EL = left_env(TM)
#        ER = right_env(TM)
#
#        @tensor a = EL[4; 1 2] * AL1[1 3; 6] * O[2 5; 3 8] * conj(AL1[4 5; 7]) * ER[6 8; 7]
#        @tensor b = EL[4; 1 2] * AL1[1 3; 6] * T[2 5; 3 8] * conj(AL1[4 5; 7]) * ER[6 8; 7]
#
#        return real(a/b)
#    end
#    ad1 = _F'(T)
#    ad2 = _F'(T)
#    @show norm(ad1), norm(ad2)
#    @test norm(ad1 - ad2) < 1e-8
#
#    for ix in []
#        sX = random_real_symmetric_tensor(2)
#        
#        test_ADgrad(_F, T; α=1e-4, tol=1e-4, sX=sX, num=1)
#    end
#end
