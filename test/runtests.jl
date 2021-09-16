using AWS
using AWS: AWSExceptions.AWSException
using AWSTools
using Dates
using Documenter
using HTTP
using Memento
using Mocking
using OrderedCollections: OrderedDict
using Test

import AWSTools.Docker
using AWSTools: account_id
using AWSTools.CloudFormation: raw_stack_description, stack_output
using AWSTools.EC2: instance_availability_zone, instance_region
using AWSTools.ECR: get_login

Memento.config!("debug"; fmt="[{level} | {name}]: {msg}")
 # Need this so that submodules are able to use the debug log level
setlevel!(getlogger(AWSTools), "debug")

Mocking.activate()

include("patch.jl")

"""
    describe_stack_string(throttle_count::Integer=0) -> String

Returns the expected xml string for CloudFormation tests.
Pass in a throttle count for throttling.
"""
function describe_stack_string(throttle_count::Integer=0)
    result = """
      <DescribeStacksResponse xmlns="http://cloudformation.amazonaws.com/doc/2010-05-15/">
        <DescribeStacksResult>
            <Stacks>
              <member>
                <StackId>Stack Id</StackId>
                <StackName>Stack Name</StackName>
                <Description>Stack Description</Description>
                $(throttle_count > 0 ? "<ThrottleCount>$throttle_count</ThrottleCount>" : "")
              </member>
            </Stacks>
        </DescribeStacksResult>
      </DescribeStacksResponse>
      """

    return replace(result, r"^\s*\n"m => "")
end

# TODO: Include in Base
function Base.convert(::Type{Vector{String}}, cmd::Cmd)
    cmd.exec
end

@testset "AWSTools Tests" begin
    include("timeout.jl")
    include("EC2.jl")

    @testset "account_id" begin
        apply(get_caller_identity_patch) do
            @test occursin(r"^\d{12}$", account_id())
        end
    end

    @testset "assume_role" begin
        apply(sts_assume_role) do
            result = AWSTools.assume_role("TestArn")

            @test isa(result.credentials, AWSCredentials)
            @test isa(result.credentials.renew, Function)
        end
    end

    @testset "CloudFormation" begin
        apply(describe_stacks_patch) do

            @testset "raw_stack_description" begin
                resp = raw_stack_description("stackname")
                @test resp == describe_stack_string()
                @test_throws AWSException begin
                    creds = AWSCredentials(invalid_access_key, invalid_secret_key)
                    raw_stack_description("stackname"; config=AWSConfig(; creds=creds))
                end
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

                outputs = stack_output("export")
                @test outputs == Dict("Key" => "Value")
            end
        end
    end


    @testset "raw_stack_description throttling" begin
        allow = [1, 3, 5, 7, 8, 11, 13, 14, 15, 16]
        apply(throttle_patch(allow)) do
            for i in allow
                resp = raw_stack_description("stackname")
                @test resp == describe_stack_string(i)
            end
        end
    end

    @testset "ECR" begin
        @testset "Basic login" begin
            apply(get_authorization_token_no_param_patch) do
                docker_login = get_login()
                @test docker_login ==
                      `docker login -u AWS -p password https://000000000000.dkr.ecr.us-east-1.amazonaws.com`
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

    doctest(AWSTools)
end
