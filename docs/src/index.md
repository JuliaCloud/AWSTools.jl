# AWSTools
[![latest](https://img.shields.io/badge/docs-latest-blue.svg)](https://invenia.pages.invenia.ca/AWSTools.jl/)
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

### S3

#### Exported

```@docs
AWSTools.S3.upload
```

#### Internal use

```@docs
AWSTools.S3.list_files(::FilePathsBase.AbstractPath)
AWSTools.S3.list_files(::AWSTools.S3.S3Path)
AWSTools.S3.cleanup_empty_folders(::FilePathsBase.AbstractPath)
AWSTools.S3.sync_key(::FilePathsBase.AbstractPath, ::FilePathsBase.AbstractPath)
AWSTools.S3.should_sync
```
