using Base: CmdRedirect
using AWSCore: AWSConfig
using Compat.Base64

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

copy_object_patch = Dict(
    1 => (
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

            args = Dict{Symbol, String}(
                :bucket => bucket,
                :path => path,
                :to_bucket => to_bucket,
                :to_path => to_path,
            )

            objects = [
                Dict(
                    :to_bucket => "bucket-2",
                    :to_path => "file1",
                    :bucket => "bucket-1",
                    :path => "file1",
                ),
                Dict(
                    :to_bucket => "bucket-2",
                    :to_path => "file2",
                    :bucket => "bucket-1",
                    :path => "file2",
                ),
                Dict(
                    :to_bucket => "bucket-2",
                    :to_path => "folder1/file3",
                    :bucket => "bucket-1",
                    :path => "folder1/file3",
                ),
            ]

            @test args in objects
        end
    ),
    2 => (
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

            args = Dict{Symbol, String}(
                :bucket => bucket,
                :path => path,
                :to_bucket => to_bucket,
                :to_path => to_path,
            )

            objects = [
                Dict(
                    :to_bucket => "bucket-2",
                    :to_path => "file",
                    :bucket => "bucket-1",
                    :path => "dir1/file",
                ),
                Dict(
                    :to_bucket => "bucket-2",
                    :to_path => "folder1/file",
                    :bucket => "bucket-1",
                    :path => "dir1/folder1/file",
                ),
            ]

            @test args in objects
        end
    ),
    3 => (
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

            args = Dict{Symbol, String}(
                :bucket => bucket,
                :path => path,
                :to_bucket => to_bucket,
                :to_path => to_path,
            )

            objects = [
                Dict(
                    :to_bucket => "bucket-1",
                    :to_path => "dir2/file",
                    :bucket => "bucket-1",
                    :path => "dir1/file",
                ),
                Dict(
                    :to_bucket => "bucket-1",
                    :to_path => "dir2/folder1/file",
                    :bucket => "bucket-1",
                    :path => "dir1/folder1/file",
                ),
            ]

            @test args in objects
        end
    ),
    4 => (
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

            args = Dict{Symbol, String}(
                :bucket => bucket,
                :path => path,
                :to_bucket => to_bucket,
                :to_path => to_path,
            )

            objects = [
                Dict(
                    :to_bucket => "bucket-2",
                    :to_path => "dir2/file",
                    :bucket => "bucket-1",
                    :path => "dir1/file",
                ),
                Dict(
                    :to_bucket => "bucket-2",
                    :to_path => "dir2/folder1/file",
                    :bucket => "bucket-1",
                    :path => "dir1/folder1/file",
                ),
            ]

            @test args in objects
        end
    ),
    5 => (
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

            args = Dict{Symbol, String}(
                :bucket => bucket,
                :path => path,
                :to_bucket => to_bucket,
                :to_path => to_path,
            )

            objects = [
                Dict(
                    :to_bucket => "bucket-2",
                    :to_path => "dir2/file1",
                    :bucket => "bucket-1",
                    :path => "file1",
                ),
                Dict(
                    :to_bucket => "bucket-2",
                    :to_path => "dir2/file2",
                    :bucket => "bucket-1",
                    :path => "file2",
                ),
                Dict(
                    :to_bucket => "bucket-2",
                    :to_path => "dir2/folder1/file3",
                    :bucket => "bucket-1",
                    :path => "folder1/file3",
                ),
            ]

            @test args in objects
        end
    ),
)

put_object_patch = Dict(
    6 => (
        @patch function s3_put(
            config::AWSConfig,
            bucket,
            path,
            data::Union{String, Vector{UInt8}};
            kwargs...,
        )
            args = Dict{Symbol, String}(:bucket => bucket, :path => path, :data => data)

            objects = [
                Dict(:bucket => "bucket-1", :path => "file", :data => "Hello World!"),
                Dict(:bucket => "bucket-1", :path => "folder/file", :data => ""),
            ]

            @test args in objects
        end
    ),
)

get_object_patch = Dict(
    7 => (
        @patch function s3_get(config::AWSConfig, bucket, path; kwargs...)
            args = Dict{Symbol, String}(:bucket => bucket, :path => path)

            objects = Dict(
                Dict(:bucket => "bucket-1", :path => "file1") => "Hello World!",
                Dict(:bucket => "bucket-1", :path => "file2") => "",
                Dict(:bucket => "bucket-1", :path => "folder1/file3") => "Test",
            )

            return objects[args]
        end
    ),
)

delete_object_patch = Dict(
    1 => (
        @patch function s3_delete(config::AWSConfig, bucket, path; kwargs...)
            @test false
        end
    ),
    2 => (
        @patch function s3_delete(config::AWSConfig, bucket, path; kwargs...)
            @test false
        end
    ),
    3 => (
        @patch function s3_delete(config::AWSConfig, bucket, path; kwargs...)
            args = Dict{Symbol, String}(:bucket => bucket, :path => path)

            objects = [
                Dict(:bucket => "bucket-1", :path =>"dir2/file2"),
                Dict(:bucket => "bucket-1", :path =>"dir2/folder2/file2"),
            ]

            @test args in objects
        end
    ),
    4 => (
        @patch function s3_delete(config::AWSConfig, bucket, path; kwargs...)
            args = Dict{Symbol, String}(:bucket => bucket, :path => path)

            objects = [
                Dict(:bucket => "bucket-2", :path =>"dir2/file2"),
                Dict(:bucket => "bucket-2", :path =>"dir2/folder2/file2"),
            ]

            @test args in objects
        end
    ),
    5 => (
        @patch function s3_delete(config::AWSConfig, bucket, path; kwargs...)
            args = Dict{Symbol, String}(:bucket => bucket, :path => path)

            objects = [
                Dict(:bucket => "bucket-2", :path =>"dir2/folder2/file3"),
            ]

            @test args in objects
        end
    ),
    6 => (
        @patch function s3_delete(config::AWSConfig, bucket, path; kwargs...)
            args = Dict{Symbol, String}(:bucket => bucket, :path => path)

            objects = [
                Dict(:bucket => "bucket-1", :path =>"file1"),
                Dict(:bucket => "bucket-1", :path =>"file2"),
                Dict(:bucket => "bucket-1", :path =>"folder1/file3"),
            ]

            @test args in objects
        end
    ),
)

list_S3_objects_patch = Dict(
    1 => (
        @patch function _s3_list_objects(config::AWSConfig, bucket, prefix)
            args = Dict{Symbol, String}(:bucket => bucket, :prefix => prefix)

            results = Dict(
                Dict(:bucket => "bucket-1", :prefix => "") => Dict{String, String}[
                    Dict(
                        "Key" => "file1",
                        "Size" => "12",
                        "LastModified" => "2018-06-27T15:19:55.000Z",
                    ),
                    Dict(
                        "Key" => "file2",
                        "Size" => "0",
                        "LastModified" => "2018-06-27T15:19:55.000Z",
                    ),
                    Dict(
                        "Key" => "folder1/file3",
                        "Size" => "4",
                        "LastModified" => "2018-06-27T15:19:55.000Z",
                    ),
                ],
                Dict(:bucket => "bucket-1", :prefix => "folder1/file3") => Dict{String, String}[
                    Dict(
                        "Key" => "folder1/file3",
                        "Size" => "4",
                        "LastModified" => "2018-06-27T15:19:55.000Z",
                    ),
                ],
                Dict(:bucket => "bucket-1", :prefix => "file2") => Dict{String, String}[
                    Dict(
                        "Key" => "file2",
                        "Size" => "0",
                        "LastModified" => "2018-06-27T15:19:55.000Z",
                    ),
                ],
                Dict(:bucket => "bucket-2", :prefix => "file1") => Dict{String, String}[],
                Dict(:bucket => "bucket-2", :prefix => "") => Dict{String, String}[],
                Dict(:bucket => "bucket-1", :prefix => "file1") => Dict{String, String}[
                    Dict(
                        "Key" => "file1",
                        "Size" => "12",
                        "LastModified" => "2018-06-27T15:19:55.000Z",
                    ),
                ],
                Dict(:bucket => "bucket-2", :prefix => "file2") => Dict{String, String}[],
                Dict(:bucket => "bucket-2", :prefix => "folder1/file3") => Dict{String, String}[],
            )

            return results[args]
        end
    ),
    2 => (
        @patch function _s3_list_objects(config::AWSConfig, bucket, prefix)
            args = Dict{Symbol, String}(:bucket => bucket, :prefix => prefix)

            results = Dict(
                Dict(:bucket => "bucket-1", :prefix => "dir1/") => Dict{String, String}[
                    Dict(
                        "Key" => "dir1/file",
                        "Size" => "12",
                        "LastModified" => "2018-06-27T15:19:55.000Z",
                    ),
                    Dict(
                        "Key" => "dir1/folder1/file",
                        "Size" => "4",
                        "LastModified" => "2018-06-27T15:19:55.000Z",
                    ),
                ],
                Dict(:bucket => "bucket-2", :prefix => "") => Dict{String, String}[],
                Dict(:bucket => "bucket-2", :prefix => "file") => Dict{String, String}[],
                Dict(:bucket => "bucket-1", :prefix => "dir1/file") => Dict{String, String}[
                    Dict(
                        "Key" => "dir1/file",
                        "Size" => "12",
                        "LastModified" => "2018-06-27T15:19:55.000Z",
                    ),
                ],
                Dict(:bucket => "bucket-2", :prefix => "folder1/file") => Dict{String, String}[],
                Dict(:bucket => "bucket-1", :prefix => "dir1/folder1/file") => Dict{String, String}[
                    Dict(
                        "Key" => "dir1/folder1/file",
                        "Size" => "4",
                        "LastModified" => "2018-06-27T15:19:55.000Z",
                    ),
                ],
            )

            return results[args]
        end
    ),
    3 => (
        @patch function _s3_list_objects(config::AWSConfig, bucket, prefix)
            args = Dict{Symbol, String}(:bucket => bucket, :prefix => prefix)

            results = Dict(
                Dict(:bucket => "bucket-1", :prefix => "dir1/folder1/file") => Dict{String, String}[
                    Dict(
                        "Key" => "dir1/folder1/file",
                        "Size" => "4",
                        "LastModified" => "2018-06-27T15:19:55.000Z",
                    ),
                ],
                Dict(:bucket => "bucket-1", :prefix => "dir1/") => Dict{String, String}[
                    Dict(
                        "Key" => "dir1/file",
                        "Size" => "12",
                        "LastModified" => "2018-06-27T15:19:55.000Z",
                    ),
                    Dict(
                        "Key" => "dir1/folder1/file",
                        "Size" => "4",
                        "LastModified" => "2018-06-27T15:19:55.000Z",
                    ),
                ],
                Dict(:bucket => "bucket-1", :prefix => "dir2/folder2/file2") => Dict{String, String}[
                    Dict(
                        "Key" => "dir2/folder2/file2",
                        "Size" => "4",
                        "LastModified" => "2018-06-27T15:19:55.000Z",
                    ),
                ],
                Dict(:bucket => "bucket-1", :prefix => "dir2/folder1/file") => Dict{String, String}[],
                Dict(:bucket => "bucket-1", :prefix => "dir1/file") => Dict{String, String}[
                    Dict(
                        "Key" => "dir1/file",
                        "Size" => "12",
                        "LastModified" => "2018-06-27T15:19:55.000Z",
                    ),
                ],
                Dict(:bucket => "bucket-1", :prefix => "dir2/") => Dict{String, String}[
                    Dict(
                        "Key" => "dir2/folder2/file2",
                        "Size" => "4",
                        "LastModified" => "2018-06-27T15:19:55.000Z",
                    ),
                ],
                Dict(:bucket => "bucket-1", :prefix => "dir2/file") => Dict{String, String}[],
            )

            return results[args]
        end
    ),
    4 => (
        @patch function _s3_list_objects(config::AWSConfig, bucket, prefix)
            args = Dict{Symbol, String}(:bucket => bucket, :prefix => prefix)

            results = Dict(
                Dict(:bucket => "bucket-1", :prefix => "dir1/") => Dict{String, String}[
                    Dict(
                        "Key" => "dir1/file",
                        "Size" => "12",
                        "LastModified" => "2018-06-27T15:19:55.000Z",
                    ),
                    Dict(
                        "Key" => "dir1/folder1/file",
                        "Size" => "4",
                        "LastModified" => "2018-06-27T15:19:55.000Z",
                    ),
                ],
                Dict(:bucket => "bucket-2", :prefix => "dir2/file") => Dict{String, String}[],
                Dict(:bucket => "bucket-2", :prefix => "dir2/folder1/file") => Dict{String, String}[],
                Dict(:bucket => "bucket-2", :prefix => "dir2/") => Dict{String, String}[
                    Dict(
                        "Key" => "dir2/file2",
                        "Size" => "12",
                        "LastModified" => "2018-06-27T15:19:55.000Z",
                    ),
                ],
                Dict(:bucket => "bucket-1", :prefix => "dir1/file") => Dict{String, String}[
                    Dict(
                        "Key" => "dir1/file",
                        "Size" => "12",
                        "LastModified" => "2018-06-27T15:19:55.000Z",
                    ),
                ],
                Dict(:bucket => "bucket-2", :prefix => "dir2/file2") => Dict{String, String}[
                    Dict(
                        "Key" => "dir2/file2",
                        "Size" => "12",
                        "LastModified" => "2018-06-27T15:19:55.000Z",
                    ),
                ],
                Dict(:bucket => "bucket-1", :prefix => "dir1/folder1/file") => Dict{String, String}[
                    Dict(
                        "Key" => "dir1/folder1/file",
                        "Size" => "4",
                        "LastModified" => "2018-06-27T15:19:55.000Z",
                    ),
                ],
            )

            return results[args]
        end
    ),
    5 => (
        @patch function _s3_list_objects(config::AWSConfig, bucket, prefix)
            args = Dict{Symbol, String}(:bucket => bucket, :prefix => prefix)

            results = Dict(
                Dict(:bucket => "bucket-1", :prefix => "") => Dict{String, String}[
                    Dict(
                        "Key" => "file1",
                        "Size" => "12",
                        "LastModified" => "2018-06-27T15:19:55.000Z",
                    ),
                    Dict(
                        "Key" => "file2",
                        "Size" => "0",
                        "LastModified" => "2018-06-27T15:19:55.000Z",
                    ),
                    Dict(
                        "Key" => "folder1/file3",
                        "Size" => "4",
                        "LastModified" => "2018-06-27T15:19:55.000Z",
                    ),
                ],
                Dict(:bucket => "bucket-1", :prefix => "folder1/file3") => Dict{String, String}[
                    Dict(
                        "Key" => "folder1/file3",
                        "Size" => "4",
                        "LastModified" => "2018-06-27T15:19:55.000Z",
                    ),
                ],
                Dict(:bucket => "bucket-1", :prefix => "file2") => Dict{String, String}[
                    Dict(
                        "Key" => "file2",
                        "Size" => "0",
                        "LastModified" => "2018-06-27T15:19:55.000Z",
                    ),
                ],
                Dict(:bucket => "bucket-2", :prefix => "dir2/folder2/file3") => Dict{String, String}[
                    Dict(
                        "Key" => "dir2/folder2/file3",
                        "Size" => "4",
                        "LastModified" => "2018-06-27T15:19:55.000Z",
                    ),
                ],
                Dict(:bucket => "bucket-1", :prefix => "file1") => Dict{String, String}[
                    Dict(
                        "Key" => "file1",
                        "Size" => "12",
                        "LastModified" => "2018-06-27T15:19:55.000Z",
                    ),
                ],
                Dict(:bucket => "bucket-2", :prefix => "dir2/file1") => Dict{String, String}[],
                Dict(:bucket => "bucket-2", :prefix => "dir2/") => Dict{String, String}[
                    Dict(
                        "Key" => "dir2/file2",
                        "Size" => "12",
                        "LastModified" => "2018-06-27T15:19:55.000Z",
                    ),
                    Dict(
                        "Key" => "dir2/folder2/file3",
                        "Size" => "4",
                        "LastModified" => "2018-06-27T15:19:55.000Z",
                    ),
                ],
                Dict(:bucket => "bucket-2", :prefix => "dir2/folder1/file3") => Dict{String, String}[],
                Dict(:bucket => "bucket-2", :prefix => "dir2/file2") => Dict{String, String}[
                    Dict(
                        "Key" => "dir2/file2",
                        "Size" => "12",
                        "LastModified" => "2018-06-27T15:19:55.000Z",
                    ),
                ],
            )

            return results[args]
        end
    ),
    6 => (
        @patch function _s3_list_objects(config::AWSConfig, bucket, prefix)
            args = Dict{Symbol, String}(:bucket => bucket, :prefix => prefix)

            results = Dict(
                Dict(:bucket => "bucket-1", :prefix => "") => Dict{String, String}[
                    Dict(
                        "Key" => "file1",
                        "Size" => "12",
                        "LastModified" => "2018-06-27T15:19:55.000Z",
                    ),
                    Dict(
                        "Key" => "file2",
                        "Size" => "0",
                        "LastModified" => "2018-06-27T15:19:55.000Z",
                    ),
                    Dict(
                        "Key" => "folder1/file3",
                        "Size" => "4",
                        "LastModified" => "2018-06-27T15:19:55.000Z",
                    ),
                ],
                Dict(:bucket => "bucket-1", :prefix => "folder1/file3") => Dict{String, String}[
                    Dict(
                        "Key" => "folder1/file3",
                        "Size" => "4",
                        "LastModified" => "2018-06-27T15:19:55.000Z",
                    ),
                ],
                Dict(:bucket => "bucket-1", :prefix => "file2") => Dict{String, String}[
                    Dict(
                        "Key" => "file2",
                        "Size" => "0",
                        "LastModified" => "2018-06-27T15:19:55.000Z",
                    ),
                ],
                Dict(:bucket => "bucket-1", :prefix => "file") => Dict{String, String}[],
                Dict(:bucket => "bucket-1", :prefix => "file1") => Dict{String, String}[
                    Dict(
                        "Key" => "file1",
                        "Size" => "12",
                        "LastModified" => "2018-06-27T15:19:55.000Z",
                    ),
                ],
                Dict(:bucket => "bucket-1", :prefix => "folder/file") => Dict{String, String}[],
            )

            return results[args]
        end
    ),
    7 => (
        @patch function _s3_list_objects(config::AWSConfig, bucket, prefix)
            args = Dict{Symbol, String}(:bucket => bucket, :prefix => prefix)

            results = Dict(
                Dict(:bucket => "bucket-1", :prefix => "") => Dict{String, String}[
                    Dict(
                        "Key" => "file1",
                        "Size" => "12",
                        "LastModified" => "2018-06-27T15:19:55.000Z",
                    ),
                    Dict(
                        "Key" => "file2",
                        "Size" => "0",
                        "LastModified" => "2018-06-27T15:19:55.000Z",
                    ),
                    Dict(
                        "Key" => "folder1/file3",
                        "Size" => "4",
                        "LastModified" => "2018-06-27T15:19:55.000Z",
                    ),
                ],
                Dict(:bucket => "bucket-1", :prefix => "folder1/file3") => Dict{String, String}[
                    Dict(
                        "Key" => "folder1/file3",
                        "Size" => "4",
                        "LastModified" => "2018-06-27T15:19:55.000Z",
                    ),
                ],
                Dict(:bucket => "bucket-1", :prefix => "file2") => Dict{String, String}[
                    Dict(
                        "Key" => "file2",
                        "Size" => "0",
                        "LastModified" => "2018-06-27T15:19:55.000Z",
                    ),
                ],
                Dict(:bucket => "bucket-1", :prefix => "file1") => Dict{String, String}[
                    Dict(
                        "Key" => "file1",
                        "Size" => "12",
                        "LastModified" => "2018-06-27T15:19:55.000Z",
                    ),
                ],
            )

            return results[args]
        end
    ),
    8 => (
        @patch function _s3_list_objects(config::AWSConfig, bucket, prefix)
            args = Dict{Symbol, String}(:bucket => bucket, :prefix => prefix)

            results = Dict(
                Dict(:bucket => "bucket", :prefix => "test_file") => Dict{String, String}[
                    Dict(
                        "Key" => "test_file",
                        "Size" => "0",
                        "LastModified" => "2018-06-27T15:19:55.000Z",
                    ),
                ],
            )

            return results[args]
        end
    ),
)





