using Test
using ArviZ
using ArviZ.ArviZStats
using DimensionalData
using Random
using StatsBase

Random.seed!(87)

@testset "utils" begin
    @testset "log_likelihood" begin
        ndraws = 100
        nchains = 4
        nparams = 3
        x = randn(ndraws, nchains, nparams)
        log_like = convert_to_dataset((; x))
        @test ArviZStats.log_likelihood(log_like) == x
        @test ArviZStats.log_likelihood(log_like, :x) == x
        @test_throws Exception ArviZStats.log_likelihood(log_like, :y)
        idata = InferenceData(; log_likelihood=log_like)
        @test ArviZStats.log_likelihood(idata) == x
        @test ArviZStats.log_likelihood(idata, :x) == x
        @test_throws Exception ArviZStats.log_likelihood(idata, :y)

        y = randn(ndraws, nchains)
        log_like = convert_to_dataset((; x, y))
        @test_throws Exception ArviZStats.log_likelihood(log_like)
        @test ArviZStats.log_likelihood(log_like, :x) == x
        @test ArviZStats.log_likelihood(log_like, :y) == y

        idata = InferenceData(; log_likelihood=log_like)
        @test_throws Exception ArviZStats.log_likelihood(idata)
        @test ArviZStats.log_likelihood(idata, :x) == x
        @test ArviZStats.log_likelihood(idata, :y) == y

        # test old InferenceData versions
        sample_stats = convert_to_dataset((; lp=randn(ndraws, nchains), log_likelihood=x))
        idata = InferenceData(; sample_stats)
        @test ArviZStats.log_likelihood(idata) == x

        sample_stats = convert_to_dataset((; lp=randn(ndraws, nchains), log_like=x))
        idata = InferenceData(; sample_stats)
        @test_throws Exception ArviZStats.log_likelihood(idata)
        @test ArviZStats.log_likelihood(idata, :log_like) == x
    end

    @testset "sigdigits_matching_error" begin
        @test ArviZStats.sigdigits_matching_error(123.456, 0.01) == 5
        @test ArviZStats.sigdigits_matching_error(123.456, 1) == 3
        @test ArviZStats.sigdigits_matching_error(123.456, 0.0001) == 7
        @test ArviZStats.sigdigits_matching_error(1e5, 0.1) == 7
        @test ArviZStats.sigdigits_matching_error(1e5, 0.2; scale=5) == 6
        @test ArviZStats.sigdigits_matching_error(1e4, 0.5) == 5
        @test ArviZStats.sigdigits_matching_error(1e4, 0.5; scale=1) == 6
        @test ArviZStats.sigdigits_matching_error(1e5, 0.1; sigdigits_max=2) == 2

        # errors
        @test_throws ArgumentError ArviZStats.sigdigits_matching_error(123.456, -1)
        @test_throws ArgumentError ArviZStats.sigdigits_matching_error(
            123.456, 1; sigdigits_max=-1
        )
        @test_throws ArgumentError ArviZStats.sigdigits_matching_error(123.456, 1; scale=-1)

        # edge cases
        @test ArviZStats.sigdigits_matching_error(0.0, 1) == 0
        @test ArviZStats.sigdigits_matching_error(NaN, 1) == 0
        @test ArviZStats.sigdigits_matching_error(Inf, 1) == 0
        @test ArviZStats.sigdigits_matching_error(100, 1; scale=Inf) == 0
        @test ArviZStats.sigdigits_matching_error(100, Inf) == 0
        @test ArviZStats.sigdigits_matching_error(100, 0) == 7
        @test ArviZStats.sigdigits_matching_error(100, 0; sigdigits_max=2) == 2
    end

    @testset "_draw_chains_params_array" begin
        chaindim = Dim{:chain}(1:4)
        drawdim = Dim{:draw}(1:2:200)
        paramdim1 = Dim{:param1}(0:1)
        paramdim2 = Dim{:param2}([:a, :b, :c])
        dims = (drawdim, chaindim, paramdim1, paramdim2)
        x = DimArray(randn(size(dims)), dims)
        xperm = permutedims(x, (chaindim, drawdim, paramdim1, paramdim2))
        @test @inferred ArviZStats._draw_chains_params_array(xperm) ≈ x
        xperm = permutedims(x, (paramdim1, chaindim, drawdim, paramdim2))
        @test @inferred ArviZStats._draw_chains_params_array(xperm) ≈ x
        xperm = permutedims(x, (paramdim1, drawdim, paramdim2, chaindim))
        @test @inferred ArviZStats._draw_chains_params_array(xperm) ≈ x
    end

    @testset "_logabssubexp" begin
        x, y = rand(2)
        @test @inferred(ArviZStats._logabssubexp(log(x), log(y))) ≈ log(abs(x - y))
        @test ArviZStats._logabssubexp(log(y), log(x)) ≈ log(abs(y - x))
    end

    @testset "_sum_and_se" begin
        @testset for n in (100, 1_000), scale in (1, 5)
            x = randn(n) * scale
            s, se = @inferred ArviZ.ArviZStats._sum_and_se(x)
            @test s ≈ sum(x)
            @test se ≈ StatsBase.sem(x) * n

            x = randn(n, 10) * scale
            s, se = @inferred ArviZ.ArviZStats._sum_and_se(x; dims=1)
            @test s ≈ sum(x; dims=1)
            @test se ≈ mapslices(StatsBase.sem, x; dims=1) * n

            x = randn(10, n) * scale
            s, se = @inferred ArviZ.ArviZStats._sum_and_se(x; dims=2)
            @test s ≈ sum(x; dims=2)
            @test se ≈ mapslices(StatsBase.sem, x; dims=2) * n
        end
        @testset "::Number" begin
            @test isequal(ArviZ.ArviZStats._sum_and_se(2), (2, NaN))
            @test isequal(ArviZ.ArviZStats._sum_and_se(3.5f0; dims=()), (3.5f0, NaN32))
        end
    end

    @testset "_log_mean" begin
        x = rand(1000)
        logx = log.(x)
        w = rand(1000)
        w ./= sum(w)
        logw = log.(w)
        @test ArviZStats._log_mean(logx, logw) ≈ log(mean(x, StatsBase.fweights(w)))
        x = rand(1000, 4)
        logx = log.(x)
        @test ArviZStats._log_mean(logx, logw; dims=1) ≈
            log.(mean(x, StatsBase.fweights(w); dims=1))
    end

    @testset "_se_log_mean" begin
        ndraws = 1_000
        @testset for n in (1_000, 10_000), scale in (1, 5)
            x = rand(n) * scale
            w = rand(n)
            w = StatsBase.weights(w ./ sum(w))
            logx = log.(x)
            logw = log.(w)
            se = @inferred ArviZStats._se_log_mean(logx, logw)
            se_exp = std(log(mean(rand(n) * scale, w)) for _ in 1:ndraws)
            @test se ≈ se_exp rtol = 1e-1
        end
    end
end