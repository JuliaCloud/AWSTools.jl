# AWSTools
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
  - s3:ListBucket
  - s3:PutObject
  - s3:DeleteObject

## Basic Usage

This example uses the Docker module directly and the ECR module indirectly. See the API for other uses of AWSTools.

```julia
julia> using AWSTools

julia> using AWSTools.Docker

julia> Docker.login()
WARNING! Using --password via the CLI is insecure. Use --password-stdin.
Login Succeeded
true

```

## API

```@docs
AWSTools.assume_role
```

### CloudFormation

```@docs
AWSTools.CloudFormation.raw_stack_description(::AbstractString)
AWSTools.CloudFormation.stack_output(::AbstractString)
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
AWSTools.ECR.get_login
```

### EC2

```@docs
AWSTools.EC2.instance_metadata(::AbstractString)
AWSTools.EC2.instance_availability_zone()
AWSTools.EC2.instance_region()
```
