# AWSTools
[![stable](https://img.shields.io/badge/docs-stable-blue.svg)](https://doc.invenia.ca/invenia/AWSTools.jl/master)
[![latest](https://img.shields.io/badge/docs-latest-blue.svg)](https://doc.invenia.ca/invenia/AWSTools.jl/master)
[![build status](https://gitlab.invenia.ca/invenia/AWSTools.jl/badges/master/build.svg)](https://gitlab.invenia.ca/invenia/AWSTools.jl/commits/master)
[![coverage](https://gitlab.invenia.ca/invenia/AWSTools.jl/badges/master/coverage.svg)](https://gitlab.invenia.ca/invenia/AWSTools.jl/commits/master)

AWSTools provides several helper methods for working with AWSSDK.jl from julia.

## Installation

```julia
julia> Pkg.add("AWSTools.jl")
```

You will also need to have the proper IAM permissions for the actions you wish to perform. 
Currently the permissions AWSTools requires (if run in it's entirety) are:
  - cloudformation:DescribeStacks
  - ecr:GetAuthorizationToken
  - s3:GetObject

## Basic Usage

This example is using the ECR module. See the API for other uses of AWSTools.

```julia
julia> using AWSTools

julia> import AWSTools.ECR: get_login

julia> docker_login = get_login()
`docker login -u AWS -p 00000...00000 https://000000000000.dkr.ecr.us-east-1.amazonaws.com`

julia> success(pipeline(docker_login, stdout=STDOUT, stderr=STDERR))
WARNING! Using --password via the CLI is insecure. Use --password-stdin.
Login Succeeded
true

```

## API

### CloudFormation

```@docs
AWSTools.CloudFormation.stack_description(::AbstractString)
```

### Docker

```@docs
AWSTools.Docker.login()
AWSTools.Docker.pull(::AbstractString)
AWSTools.Docker.push(::AbstractString)
AWSTools.Docker.build(::AbstractString, ::AbstractString)
```

### ECR

```@docs
AWSTools.ECR.get_login(::Vector{<:Integer}=Int[])
```

### S3

```@docs
AWSTools.S3.S3Results
```
