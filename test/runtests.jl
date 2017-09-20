using Mocking
Mocking.enable()

using Base.Test
using AWSTools
using Memento
using AWSSDK

import AWSSDK.Batch: describe_job_definitions

const PKG_DIR = abspath(dirname(@__FILE__), "..")
const REV = cd(() -> readchomp(`git rev-parse HEAD`), PKG_DIR)
const IMAGE_DEFINITION = "292522074875.dkr.ecr.us-east-1.amazonaws.com/aws-tools:latest"
const JOB_ROLE = "arn:aws:iam::292522074875:role/AWSBatchClusterManagerJobRole"
const JOB_DEFINITION = "AWSTools"
const JOB_NAME = "AWSToolTest"
const JOB_QUEUE = "Replatforming-Manager"

Memento.config("info"; fmt="[{level} | {name}]: {msg}")

include("mock.jl")

@testset "AWSTools" begin
    @testset "Job Construction" begin
        @testset "Defaults" begin
            job = BatchJob()

            @test job.vcpus == 1
            @test job.memory == 1024
            @test isempty(job.id)
            @test isempty(job.image)
            @test isempty(job.definition)
            @test isempty(job.role)
            @test isnull(job.output)
        end

        @testset "From Job Definition" begin
            patch = @patch describe_job_definitions(args...) = describe_jobs_def_resp

            apply(patch; debug=true) do
                job = BatchJob(name=JOB_NAME, definition="sleep60")

                @test job.cmd == `sleep 60`
                @test job.image == "busybox"
                @test isnull(job.output)
            end
        end

        @testset "From Current Job" begin
            withenv(BATCH_ENVS...) do
                patches = [
                    @patch readstring(cmd::AbstractCmd) = mock_readstring(cmd)
                    @patch describe_jobs(args...) = describe_jobs_resp
                ]

                apply(patches; debug=true) do
                    job = BatchJob()

                    @test job.memory == 128
                    @test job.image == "busybox"
                    @test isnull(job.output)
                end
            end
        end

        @testset "From Multiple" begin
            withenv(BATCH_ENVS...) do
                patches = [
                    @patch readstring(cmd::AbstractCmd) = mock_readstring(cmd)
                    @patch describe_jobs(args...) = describe_jobs_resp
                ]

                apply(patches; debug=true) do
                    job = BatchJob(output=S3Results("AWSTools", "test"))

                    @test job.memory == 128
                    @test !isnull(job.output)
                end
            end
        end
    end

    @testset "Job Submission" begin
        job = BatchJob(
            name=JOB_NAME,
            image=IMAGE_DEFINITION,
            role=JOB_ROLE,
            definition=JOB_DEFINITION,
            queue=JOB_QUEUE,
            vcpus=1,
            memory=1024,
            cmd=`julia -e 'println("Hello World!")'`,
            output=S3Results("AWSTools", "test"),
        )

        submit(job)
        wait(job, [AWSTools.SUCCEEDED])
        events = logs(job)

        @test length(events) == 1
        @test contains(first(events)["message"], "Hello World!")
    end
end
