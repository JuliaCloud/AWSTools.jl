using AWSTools: timeout

@testset "timeout" begin
    # Ensure that timeout is compiled for elapsed time tests
    timeout(() -> 0, 1)

    @testset "finish" begin
        secs = @elapsed begin
            result = timeout(() -> 0, 1)
        end
        @test result == Some(0)
        @test secs < 0.2  # Should execute almost as fast as calling the function directly
    end

    @testset "abort" begin
        secs = @elapsed begin
            result = timeout(1) do
                sleep(5)
                error("unexpected error")
            end
        end
        @test result === nothing
        @test 1 <= secs < 5
    end

    @testset "return nothing" begin
        secs = @elapsed begin
            result = timeout(() -> nothing, 1)
        end
        @test result == Some(nothing)
        @test secs < 1
        @test secs < 0.2  # Should execute almost as fast as calling the function directly
    end

    @testset "exception" begin
        local exception
        secs = @elapsed begin
            try
                timeout(() -> error("function error"), 5)
            catch e
                exception = e
            end
        end
        @test exception == ErrorException("function error")
        @test secs < 5
        @test secs < 0.2  # Should execute almost as fast as calling the function directly
    end
end
