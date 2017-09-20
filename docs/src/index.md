# AWSTools
[![stable](https://img.shields.io/badge/docs-stable-blue.svg)](https://doc.invenia.ca/invenia/AWSTools.jl/master)
[![latest](https://img.shields.io/badge/docs-latest-blue.svg)](https://doc.invenia.ca/invenia/AWSTools.jl/master)
[![build status](https://gitlab.invenia.ca/invenia/AWSTools.jl/badges/master/build.svg)](https://gitlab.invenia.ca/invenia/AWSTools.jl/commits/master)
[![coverage](https://gitlab.invenia.ca/invenia/AWSTools.jl/badges/master/coverage.svg)](https://gitlab.invenia.ca/invenia/AWSTools.jl/commits/master)

AWSTools.jl provides a small set of methods for working with AWS Batch jobs from julia.

## Installation

AWSTools assumes that you already have an AWS account configured with:

1. An [ECR repository](https://aws.amazon.com/ecr/) and a docker image pushed to it [[1]](http://docs.aws.amazon.com/AmazonECR/latest/userguide/docker-push-ecr-image.html).
2. An [IAM role](http://docs.aws.amazon.com/IAM/latest/UserGuide/id_roles.html) to apply to the batch jobs.
3. A compute environment and job queue for submitting jobs to [[2]](http://docs.aws.amazon.com/batch/latest/userguide/Batch_GetStarted.html#first-run-step-2).

Please review the
["Getting Started with AWS Batch"](http://docs.aws.amazon.com/batch/latest/userguide/Batch_GetStarted.html) guide and example
[CloudFormation template](https://s3-us-west-2.amazonaws.com/cloudformation-templates-us-west-2/Managed_EC2_Batch_Environment.template) for more details.

## Basic Usage

```julia
julia> using AWSTools

julia> using Memento

julia> Memento.config("info"; fmt="[{level} | {name}]: {msg}")
Logger(root)

julia> job = BatchJob(
           name="Demo",
           image="000000000000.dkr.ecr.us-east-1.amazonaws.com/demo:latest",
           role="arn:aws:iam::000000000000:role/AWSBatchJobRole",
           definition="AWSBatchJobDefinition",
           queue="AWSBatchJobQueue",
           vcpus=1,
           memory=1024,
           cmd=`julia -e 'println("Hello World!")'`,
           output=S3Results("Demo", "test"),
       )
AWSTools.BatchJob("", "Demo", `julia -e 'println("Hello World!")'`, "000000000000.dkr.ecr.us-east-1.amazonaws.com/demo:latest", 1, 1024, "arn:aws:iam::000000000000:role/AWSBatchJobRole", "AWSBatchJobQueue", "AWSBatchJobQueue", "", AWSTools.S3Results("Demo", "test"))

julia> submit(job)
[info | AWSTools]: Registered job definition arn:aws:batch:us-east-1:000000000000:job-definition/AWSBatchJobDefinition:1.
[info | AWSTools]: Submitted job Demo::00000000-0000-0000-0000-000000000000.
Dict{String,Any} with 2 entries:
  "jobId"   => "00000000-0000-0000-0000-000000000000"
  "jobName" => "Demo"

julia> wait(job, [AWSTools.SUCCEEDED])
[info | AWSTools]: Demo::00000000-0000-0000-0000-000000000000 status SUBMITTED
[info | AWSTools]: Demo::00000000-0000-0000-0000-000000000000 status STARTING
[info | AWSTools]: Demo::00000000-0000-0000-0000-000000000000 status SUCCEEDED
true

julia> results = logs(job)
[info | AWSTools]: Fetching log events from Demo/default/00000000-0000-0000-0000-000000000000
[info | AWSTools]: Hello World!
1-element Array{Any,1}:
 Dict{String,Any}(Pair{String,Any}("ingestionTime", 1505846649863),Pair{String,Any}("message", "Hello World!"),Pair{String,Any}("timestamp", 1505846649786),Pair{String,Any}("eventId", "00000000000000000000000000000000000000000000000000000000"))
```

## API

### Public

```@docs
AWSTools.BatchJob
AWSTools.BatchStatus
AWSTools.S3Results
AWSTools.describe
AWSTools.submit
Base.wait
AWSTools.logs
Base.download
```

### Private

```@docs
AWSTools.AbstractResults
AWSTools.def_arn
```