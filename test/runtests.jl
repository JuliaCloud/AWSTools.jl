using Mocking
Mocking.enable(force=true)

using AWSTools
using Compat: AbstractDict, occursin
using Compat.Dates
using Compat.Test
using Memento
using DataStructures: OrderedDict
using HTTP

import AWSTools.Docker
using AWSTools: account_id
using AWSTools.CloudFormation: stack_description, stack_output
using AWSTools.EC2: instance_availability_zone, instance_region
using AWSTools.ECR: get_login

Memento.config!("debug"; fmt="[{level} | {name}]: {msg}")
 # Need this so that submodules are able to use the debug log level
setlevel!(getlogger(AWSTools), "debug")

include("patch.jl")

# TODO: Include in Base
function Base.convert(::Type{Vector{String}}, cmd::Cmd)
    cmd.exec
end

@testset "AWSTools Tests" begin

    include("S3.jl")

    @testset "account_id" begin
        apply(get_caller_identity) do
            @test occursin(r"^\d{12}$", account_id())
        end
    end

    @testset "CloudFormation" begin
        apply(describe_stacks_patch) do

            @testset "stack_description" begin
                resp = stack_description("stackname")
                @test resp == Dict(
                    "StackId" => "Stack Id",
                    "StackName" => "Stack Name",
                    "Description" => "Stack Description",
                )
            end

            @testset "stack_output" begin
                outputs = stack_output("stackname")
                @test outputs == Dict()

                outputs = stack_output("1-stack-output-stackname")
                @test outputs == Dict("TestBucketArn1"=>"arn:aws:s3:::test-bucket-1")

                outputs = stack_output("multiple-stack-outputs-stackname")
                @test outputs == Dict(
                    "TestBucketArn1" => "arn:aws:s3:::test-bucket-1",
                    "TestBucketArn2" => "arn:aws:s3:::test-bucket-2",
                )

                # Empty output values
                outputs = stack_output("empty-value")
                @test outputs == Dict(
                    "ParquetConversionTriggerName" => "",
                )
            end
        end
    end


    @testset "stack_description throttling" begin
        allow = [1, 3, 5, 7, 8, 11, 13, 14, 15, 16]
        apply(throttle_patch(allow)) do
            for i in 1:10
                resp = stack_description("stackname")
                @test resp == Dict(
                    "StackId" => "Stack Id",
                    "StackName" => "Stack Name",
                    "Description" => "Stack Description",
                    "ThrottleCount" => "$(allow[i])",
                )
            end
        end
    end

    @testset "EC2" begin
        @testset "instance_availability_zone" begin
            apply(instance_availability_zone_patch) do
                @test instance_availability_zone() == "us-east-1a"
            end
        end

        @testset "instance_region" begin
            apply(instance_availability_zone_patch) do
                @test instance_region() == "us-east-1"
            end
        end
    end

    @testset "ECR" begin
        @testset "Basic login" begin
            apply(get_authorization_token_patch) do
                docker_login = get_login()
                @test docker_login == `docker login -u AWS -p password https://000000000000.dkr.ecr.us-east-1.amazonaws.com`
            end
        end

        @testset "Login specifying registry ID" begin
            apply(get_authorization_token_patch) do
                docker_login = get_login(1)
                @test docker_login == `docker login -u AWS -p password https://000000000001.dkr.ecr.us-east-1.amazonaws.com`
            end
        end
    end

    @testset "Online Tests" begin
        @testset "ECR" begin
            command = convert(Vector{String}, get_login())
            @test command[1] == "docker"
            @test command[2] == "login"
            @test command[3] == "-u"
            @test command[4] == "AWS"
            @test command[5] == "-p"
            @test length(command) == 7
        end
    end
end
