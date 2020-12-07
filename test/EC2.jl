using AWSTools.EC2: instance_metadata, instance_availability_zone, instance_region

@testset "EC2" begin
    @testset "instance_metadata" begin
        r = HTTP.Response("{}")  # Instance identity document is JSON
        apply(instance_metadata_patch(r)) do
            @test instance_metadata("/latest/dynamic/instance-identity/document") == "{}"
        end
    end

    @testset "instance_availability_zone" begin
        r = HTTP.Response("us-east-1a")
        apply(instance_metadata_patch(r)) do
            @test instance_availability_zone() == "us-east-1a"
        end
    end

    @testset "instance_region" begin
        r = HTTP.Response("us-east-1a")
        apply(instance_metadata_patch(r)) do
            @test instance_region() == "us-east-1"
        end
    end
end
