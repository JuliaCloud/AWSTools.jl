using Base: CmdRedirect
using AWSCore: AWSConfig
using Compat.Base64
using Compat: codeunits

get_caller_identity = @patch function get_caller_identity()
    account_id = join(rand(0:9, 12), "")
    Dict(
        "Account" => account_id,
        "Arn" => "arn:aws:iam::$account_id:user/UserName",
        "UserId" => join(rand('A':'Z', 21), ""),
    )
end

instance_availability_zone_patch = @patch function read(cmd::CmdRedirect, ::Type{String})
    url = cmd.cmd.exec[2]
    @test endswith(url, "availability-zone")
    return "us-east-1a"
end

get_authorization_token_patch = @patch function get_authorization_token(config::AWSConfig; registryIds::AbstractVector=[])
    id = lpad(isempty(registryIds) ? "" : first(registryIds), 12, '0')
    Dict(
        "authorizationData" => [
            Dict(
                "authorizationToken" => base64encode("AWS:password"),
                "proxyEndpoint" => "https://$(id).dkr.ecr.us-east-1.amazonaws.com"
            ),
        ]
    )
end


describe_stacks_patch = @patch function describe_stacks(args...; kwargs...)
    responses = Dict(
       Dict(:StackName => "stackname") =>
        """
        <DescribeStacksResponse xmlns="http://cloudformation.amazonaws.com/doc/2010-05-15/">
          <DescribeStacksResult>
              <Stacks>
                <member>
                  <StackId>Stack Id</StackId>
                  <StackName>Stack Name</StackName>
                  <Description>Stack Description</Description>
                </member>
              </Stacks>
          </DescribeStacksResult>
        </DescribeStacksResponse>
        """,
        Dict(:StackName => "1-stack-output-stackname") =>
        """
        <DescribeStacksResponse xmlns="http://cloudformation.amazonaws.com/doc/2010-05-15/">
          <DescribeStacksResult>
            <Stacks>
              <member>
                <Outputs>
                  <member>
                    <OutputKey>TestBucketArn1</OutputKey>
                    <OutputValue>arn:aws:s3:::test-bucket-1</OutputValue>
                  </member>
                </Outputs>
                <StackId>Stack Id</StackId>
                <StackName>Stack Name</StackName>
                <Description>Stack Description</Description>
              </member>
            </Stacks>
          </DescribeStacksResult>
        </DescribeStacksResponse>
        """,
        Dict(:StackName => "multiple-stack-outputs-stackname") =>
        """
        <DescribeStacksResponse xmlns="http://cloudformation.amazonaws.com/doc/2010-05-15/">
          <DescribeStacksResult>
            <Stacks>
              <member>
                <Outputs>
                  <member>
                    <OutputKey>TestBucketArn1</OutputKey>
                    <OutputValue>arn:aws:s3:::test-bucket-1</OutputValue>
                  </member>
                  <member>
                    <OutputKey>TestBucketArn2</OutputKey>
                    <OutputValue>arn:aws:s3:::test-bucket-2</OutputValue>
                  </member>
                </Outputs>
                <StackId>Stack Id</StackId>
                <StackName>Stack Name</StackName>
                <Description>Stack Description</Description>
              </member>
            </Stacks>
          </DescribeStacksResult>
        </DescribeStacksResponse>
        """,
        Dict(:StackName => "empty-value") =>
        """
        <DescribeStacksResponse xmlns="http://cloudformation.amazonaws.com/doc/2010-05-15/">
          <DescribeStacksResult>
            <Stacks>
              <member>
                <Outputs>
                  <member>
                    <OutputKey>ParquetConversionTriggerName</OutputKey>
                    <OutputValue></OutputValue>
                  </member>
                </Outputs>
                <StackId>Stack Id</StackId>
                <StackName>Stack Name</StackName>
                <Description>Stack Description</Description>
              </member>
            </Stacks>
          </DescribeStacksResult>
        </DescribeStacksResponse>
        """,
    )

    return responses[Dict{Symbol, String}(kwargs)]
end


function throttle_patch(allow)
    describe_stacks_throttle_count = 0
    @patch function describe_stacks(args...; kwargs...)
        describe_stacks_throttle_count += 1
        if !(describe_stacks_throttle_count in allow)
            error_message = """
                <ErrorResponse xmlns="http://cloudformation.amazonaws.com/doc/2010-05-15/">
                    <Error>
                        <Type>Sender</Type>
                        <Code>Throttling</Code>
                        <Message>Rate exceeded</Message>
                    </Error>
                    <RequestId>d0c477ac-f267-11e8-9d2b-93e3aa6368c5</RequestId>
                </ErrorResponse>
                """
            http_error = HTTP.ExceptionRequest.StatusError(400, HTTP.Messages.Response(400, error_message))
            throw(AWSException(http_error))
        end
        responses = Dict(
           Dict(:StackName => "stackname") =>
            """
            <DescribeStacksResponse xmlns="http://cloudformation.amazonaws.com/doc/2010-05-15/">
              <DescribeStacksResult>
                  <Stacks>
                    <member>
                      <StackId>Stack Id</StackId>
                      <StackName>Stack Name</StackName>
                      <Description>Stack Description</Description>
                      <ThrottleCount>$describe_stacks_throttle_count</ThrottleCount>
                    </member>
                  </Stacks>
              </DescribeStacksResult>
            </DescribeStacksResponse>
            """,
        )

        return responses[Dict{Symbol, String}(kwargs)]
    end
end


function format_s3_objects(content::AbstractDict)
    objects = OrderedDict{Tuple{String,String}, Dict{String,Any}}()
    for ((bucket::String, key::String), data) in content
        formatted_data = Dict{String, Any}(k => v for (k, v) in data)

        # Add in defaults for required keys
        get!(formatted_data, "Key", key)
        get!(formatted_data, "LastModified", "1970-01-01T00:00:00.000Z")
        get!(formatted_data, "Size") do
            len = if haskey(formatted_data, "Content")
                sizeof(formatted_data["Content"])
            else
                0
            end
            string(len)
        end

        push!(objects, (bucket, key) => formatted_data)
    end

    return objects
end

function format_s3_objects(content::AbstractVector{Pair{Tuple{String,String},D}}) where D <: AbstractDict
    format_s3_objects(OrderedDict(k => v for (k, v) in content))
end

function format_s3_objects(content::AbstractVector{Tuple{String,String}})
    format_s3_objects(OrderedDict(k => Dict() for k in content))
end


function s3_patches!(content::AbstractDict, changes::AbstractVector=[])
    return [
        @patch function _s3_list_objects(config::AWSConfig, bucket, path_prefix; kwargs...)
            results = []
            for ((b, key), data) in content
                if b == bucket && startswith(key, path_prefix)
                    push!(results, data)
                end
            end
            return results
        end

        # https://github.com/invenia/Mocking.jl/issues/59
        # @patch _s3_list_objects(args...) = _s3_list_objects(default_aws_config(), args...)

        @patch function s3_get(config::AWSConfig, bucket, path; kwargs...)
            codeunits(get(content[(bucket, path)], "Content", ""))
        end

        @patch function s3_exists(config::AWSConfig, bucket, path)
            haskey(content, (bucket, path))
        end

        @patch function s3_copy(
            config::AWSConfig,
            bucket,
            path;
            to_bucket=999999,
            to_path=999999,
            kwargs...,
        )
            # gets around:
            # https://github.com/invenia/Mocking.jl/issues/56
            # https://github.com/invenia/Mocking.jl/issues/57
            # https://github.com/invenia/Mocking.jl/issues/58
            to_bucket = to_bucket === 999999 ? bucket : to_bucket
            to_path = to_path === 999999 ? path : to_path

            push!(
                changes,
                :copy => Dict(
                    :from => (bucket, path),
                    :to => (to_bucket, to_path),
                )
            )
        end

        @patch function s3_delete(config::AWSConfig, bucket, path; kwargs...)
            push!(changes, :delete => (bucket, path))
        end

        @patch function s3_put(
            config::AWSConfig,
            bucket,
            path,
            data::Union{AbstractString, Vector{UInt8}};
            kwargs...,
        )
            push!(
                changes,
                :put => Dict(
                    :dest => (bucket, path),
                    :data => data,
                )
            )
        end
    ]
end
