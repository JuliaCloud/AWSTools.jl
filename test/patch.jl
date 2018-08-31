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

describe_stacks_patch = @patch function describe_stacks(args...)
    responses = Dict(
       Dict("StackName" => "stackname") =>
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
        Dict("StackName" => "1-stack-output-stackname") =>
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
        Dict("StackName" => "multiple-stack-outputs-stackname") =>
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
        Dict("StackName" => "empty-value") =>
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

    return responses[args[2]]
end

copy_object_patch = Dict(
    1 => (
        @patch function copy_object(config::AWSConfig, args)
            objects = [
                Dict("Bucket" => "bucket-2", "Key" => "file1", "headers" => Dict(
                    "x-amz-copy-source" => "/bucket-1/file1",
                    "x-amz-metadata-directive" => "REPLACE",
                )),
                Dict("Bucket" => "bucket-2", "Key" => "file2", "headers" => Dict(
                    "x-amz-copy-source" => "/bucket-1/file2",
                    "x-amz-metadata-directive" => "REPLACE",
                )),
                Dict("Bucket" => "bucket-2", "Key" => "folder1/file3", "headers" => Dict(
                    "x-amz-copy-source" => "/bucket-1/folder1/file3",
                    "x-amz-metadata-directive" => "REPLACE",
                )),
            ]
            @test args in objects
        end
    ),
    2 => (
        @patch function copy_object(config::AWSConfig, args)
            objects = [
                Dict("Bucket" => "bucket-2", "Key" => "file", "headers" => Dict(
                    "x-amz-copy-source" => "/bucket-1/dir1/file",
                    "x-amz-metadata-directive" => "REPLACE",
                )),
                Dict("Bucket" => "bucket-2", "Key" => "folder1/file", "headers" => Dict(
                    "x-amz-copy-source" => "/bucket-1/dir1/folder1/file",
                    "x-amz-metadata-directive" => "REPLACE",
                )),
            ]
            @test args in objects
        end
    ),
    3 => (
        @patch function copy_object(config::AWSConfig, args)
            objects = [
                Dict("Bucket" => "bucket-1", "Key" => "dir2/file", "headers" => Dict(
                    "x-amz-copy-source" => "/bucket-1/dir1/file",
                    "x-amz-metadata-directive" => "REPLACE",
                )),
                Dict("Bucket" => "bucket-1", "Key" => "dir2/folder1/file", "headers" => Dict(
                    "x-amz-copy-source" => "/bucket-1/dir1/folder1/file",
                    "x-amz-metadata-directive" => "REPLACE",
                )),
            ]
            @test args in objects
        end
    ),
    4 => (
        @patch function copy_object(config::AWSConfig, args)
            objects = [
                Dict("Bucket" => "bucket-2", "Key" => "dir2/file", "headers" => Dict(
                    "x-amz-copy-source" => "/bucket-1/dir1/file",
                    "x-amz-metadata-directive" => "REPLACE",
                )),
                Dict("Bucket" => "bucket-2", "Key" => "dir2/folder1/file", "headers" => Dict(
                    "x-amz-copy-source" => "/bucket-1/dir1/folder1/file",
                    "x-amz-metadata-directive" => "REPLACE",
                )),
            ]
            @test args in objects
        end
    ),
    5 => (
        @patch function copy_object(config::AWSConfig, args)
            objects = [
                Dict("Bucket" => "bucket-2", "Key" => "dir2/file1", "headers" => Dict(
                    "x-amz-copy-source" => "/bucket-1/file1",
                    "x-amz-metadata-directive" => "REPLACE",
                )),
                Dict("Bucket" => "bucket-2", "Key" => "dir2/file2", "headers" => Dict(
                    "x-amz-copy-source" => "/bucket-1/file2",
                    "x-amz-metadata-directive" => "REPLACE",
                )),
                Dict("Bucket" => "bucket-2", "Key" => "dir2/folder1/file3", "headers" => Dict(
                    "x-amz-copy-source" => "/bucket-1/folder1/file3",
                    "x-amz-metadata-directive" => "REPLACE",
                )),
            ]
            @test args in objects
        end
    ),
)

put_object_patch = Dict(
    6 => (
        @patch function put_object(config::AWSConfig, args)
            objects = [
                Dict("Bucket" => "bucket-1", "Body" => "Hello World!", "Key" =>"file"),
                Dict("Bucket" => "bucket-1", "Body" => "", "Key" =>"folder/file"),
            ]
            @test args in objects
        end
    ),
)

get_object_patch = Dict(
    7 => (
        @patch function get_object(config::AWSConfig, args)
            objects = Dict(
                Dict("Bucket" => "bucket-1", "Key" => "file1") => "Hello World!",
                Dict("Bucket" => "bucket-1", "Key" => "file2") => "",
                Dict("Bucket" => "bucket-1", "Key" => "folder1/file3") => "Test",
            )
            return objects[args]
        end
    ),
)

delete_object_patch = Dict(
    1 => (
        @patch function delete_object(config::AWSConfig, args)
            objects = []
            @test args in objects
        end
    ),
    2 => (
        @patch function delete_object(config::AWSConfig, args)
            objects = []
            @test args in objects
        end
    ),
    3 => (
        @patch function delete_object(config::AWSConfig, args)
            objects = [
                Dict("Bucket" => "bucket-1", "Key" =>"dir2/file2"),
                Dict("Bucket" => "bucket-1", "Key" =>"dir2/folder2/file2"),
            ]
            @test args in objects
        end
    ),
    4 => (
        @patch function delete_object(config::AWSConfig, args)
            objects = [
                Dict("Bucket" => "bucket-2", "Key" =>"dir2/file2"),
                Dict("Bucket" => "bucket-2", "Key" =>"dir2/folder2/file2"),
            ]
            @test args in objects
        end
    ),
    5 => (
        @patch function delete_object(config::AWSConfig, args)
            objects = [
                Dict("Bucket" => "bucket-2", "Key" =>"dir2/folder2/file3"),
            ]
            @test args in objects
        end
    ),
    6 => (
        @patch function delete_object(config::AWSConfig, args)
            objects = [
                Dict("Bucket" => "bucket-1", "Key" =>"file1"),
                Dict("Bucket" => "bucket-1", "Key" =>"file2"),
                Dict("Bucket" => "bucket-1", "Key" =>"folder1/file3"),
            ]
            @test args in objects
        end
    ),
)

list_S3_objects_patch = Dict(
    1 => (
        @patch function list_objects_v2(config::AWSConfig, args)
            results = Dict(
                Dict("Bucket" => "bucket-1", "prefix" => "") =>
                """
                <?xml version="1.0" encoding="utf-8"?>
                <ListBucketResult xmlns="http://s3.amazonaws.com/doc/2006-03-01/">
                    <Name></Name>
                    <Prefix/>
                    <KeyCount>3</KeyCount>
                    <MaxKeys>1000</MaxKeys>
                    <IsTruncated>false</IsTruncated>
                    <Contents>
                      <Key>file1</Key>
                      <LastModified>2018-06-27T15:19:55.000Z</LastModified>
                      <Size>12</Size>
                    </Contents>
                    <Contents>
                      <Key>file2</Key>
                      <LastModified>2018-06-27T15:19:55.000Z</LastModified>
                      <Size>0</Size>
                    </Contents>
                    <Contents>
                      <Key>folder1/file3</Key>
                      <LastModified>2018-06-27T15:19:55.000Z</LastModified>
                      <Size>4</Size>
                    </Contents>
                </ListBucketResult>
                """,
                Dict("Bucket" => "bucket-1", "prefix" => "folder1/file3") =>
                """
                <?xml version="1.0" encoding="utf-8"?>
                <ListBucketResult xmlns="http://s3.amazonaws.com/doc/2006-03-01/">
                    <Name>bucket-1</Name>
                    <Prefix>folder1/file3</Prefix>
                    <KeyCount>1</KeyCount>
                    <MaxKeys>1000</MaxKeys>
                    <IsTruncated>false</IsTruncated>
                    <Contents>
                      <Key>folder1/file3</Key>
                      <LastModified>2018-06-27T15:19:55.000Z</LastModified>
                      <Size>4</Size>
                    </Contents>
                </ListBucketResult>
                """,
                Dict("Bucket" => "bucket-1", "prefix" => "file1") =>
                """
                <?xml version="1.0" encoding="utf-8"?>
                <ListBucketResult xmlns="http://s3.amazonaws.com/doc/2006-03-01/">
                    <Name>bucket-1</Name>
                    <Prefix>file1</Prefix>
                    <KeyCount>1</KeyCount>
                    <MaxKeys>1000</MaxKeys>
                    <IsTruncated>false</IsTruncated>
                    <Contents>
                      <Key>file1</Key>
                      <LastModified>2018-06-27T15:19:55.000Z</LastModified>
                      <Size>12</Size>
                    </Contents>
                </ListBucketResult>
                """,
                Dict("Bucket" => "bucket-1", "prefix" => "file2") =>
                """
                <?xml version="1.0" encoding="utf-8"?>
                <ListBucketResult xmlns="http://s3.amazonaws.com/doc/2006-03-01/">
                    <Name>bucket-1</Name>
                    <Prefix>file2</Prefix>
                    <KeyCount>1</KeyCount>
                    <MaxKeys>1000</MaxKeys>
                    <IsTruncated>false</IsTruncated>
                    <Contents>
                      <Key>file2</Key>
                      <LastModified>2018-06-27T15:19:55.000Z</LastModified>
                      <Size>0</Size>
                    </Contents>
                </ListBucketResult>
                """,
                Dict("Bucket" => "bucket-2", "prefix" => "") =>
                """
                <?xml version="1.0" encoding="utf-8"?>
                <ListBucketResult xmlns="http://s3.amazonaws.com/doc/2006-03-01/">
                    <Name>bucket-2</Name>
                    <Prefix/>
                    <KeyCount>0</KeyCount>
                    <MaxKeys>1000</MaxKeys>
                    <IsTruncated>false</IsTruncated>
                </ListBucketResult>
                """,
                Dict("Bucket" => "bucket-2", "prefix" => "folder1/file3") =>
                """
                <?xml version="1.0" encoding="utf-8"?>
                <ListBucketResult xmlns="http://s3.amazonaws.com/doc/2006-03-01/">
                    <Name>bucket-2</Name>
                    <Prefix>folder1/file3</Prefix>
                    <KeyCount>0</KeyCount>
                    <MaxKeys>1000</MaxKeys>
                    <IsTruncated>false</IsTruncated>
                </ListBucketResult>
                """,
                Dict("Bucket" => "bucket-2", "prefix" => "file1") =>
                """
                <?xml version="1.0" encoding="utf-8"?>
                <ListBucketResult xmlns="http://s3.amazonaws.com/doc/2006-03-01/">
                    <Name>bucket-2</Name>
                    <Prefix>file1</Prefix>
                    <KeyCount>0</KeyCount>
                    <MaxKeys>1000</MaxKeys>
                    <IsTruncated>false</IsTruncated>
                </ListBucketResult>
                """,
                Dict("Bucket" => "bucket-2", "prefix" => "file2") =>
                """
                <?xml version="1.0" encoding="utf-8"?>
                <ListBucketResult xmlns="http://s3.amazonaws.com/doc/2006-03-01/">
                    <Name>bucket-2</Name>
                    <Prefix>file2</Prefix>
                    <KeyCount>0</KeyCount>
                    <MaxKeys>1000</MaxKeys>
                    <IsTruncated>false</IsTruncated>
                </ListBucketResult>
                """,
            )
            return results[args]
        end
    ),
    2 => (
        @patch function list_objects_v2(config::AWSConfig, args)
            results = Dict(
                Dict("Bucket" => "bucket-1", "prefix" => "dir1/") =>
                """
                <?xml version="1.0" encoding="utf-8"?>
                <ListBucketResult xmlns="http://s3.amazonaws.com/doc/2006-03-01/">
                    <Name></Name>
                    <Prefix>dir1/</Prefix>
                    <KeyCount>2</KeyCount>
                    <MaxKeys>1000</MaxKeys>
                    <IsTruncated>false</IsTruncated>
                    <Contents>
                      <Key>dir1/file</Key>
                      <LastModified>2018-06-27T15:19:55.000Z</LastModified>
                      <Size>12</Size>
                    </Contents>
                    <Contents>
                      <Key>dir1/folder1/file</Key>
                      <LastModified>2018-06-27T15:19:55.000Z</LastModified>
                      <Size>4</Size>
                    </Contents>
                </ListBucketResult>
                """,
                Dict("Bucket" => "bucket-1", "prefix" => "dir1/folder1/file") =>
                """
                <?xml version="1.0" encoding="utf-8"?>
                <ListBucketResult xmlns="http://s3.amazonaws.com/doc/2006-03-01/">
                    <Name></Name>
                    <Prefix>dir1/folder1/file</Prefix>
                    <KeyCount>1</KeyCount>
                    <MaxKeys>1000</MaxKeys>
                    <IsTruncated>false</IsTruncated>
                    <Contents>
                      <Key>dir1/folder1/file</Key>
                      <LastModified>2018-06-27T15:19:55.000Z</LastModified>
                      <Size>4</Size>
                    </Contents>
                </ListBucketResult>
                """,
                Dict("Bucket" => "bucket-1", "prefix" => "dir1/file") =>
                """
                <?xml version="1.0" encoding="utf-8"?>
                <ListBucketResult xmlns="http://s3.amazonaws.com/doc/2006-03-01/">
                    <Name></Name>
                    <Prefix>dir1/file</Prefix>
                    <KeyCount>1</KeyCount>
                    <MaxKeys>1000</MaxKeys>
                    <IsTruncated>false</IsTruncated>
                    <Contents>
                      <Key>dir1/file</Key>
                      <LastModified>2018-06-27T15:19:55.000Z</LastModified>
                      <Size>12</Size>
                    </Contents>
                </ListBucketResult>
                """,
                Dict("Bucket" => "bucket-2", "prefix" => "") =>
                """
                <?xml version="1.0" encoding="utf-8"?>
                <ListBucketResult xmlns="http://s3.amazonaws.com/doc/2006-03-01/">
                    <Name>bucket-2</Name>
                    <Prefix/>
                    <KeyCount>0</KeyCount>
                    <MaxKeys>1000</MaxKeys>
                    <IsTruncated>false</IsTruncated>
                </ListBucketResult>
                """,
                Dict("Bucket" => "bucket-2", "prefix" => "folder1/file") =>
                """
                <?xml version="1.0" encoding="utf-8"?>
                <ListBucketResult xmlns="http://s3.amazonaws.com/doc/2006-03-01/">
                    <Name>bucket-2</Name>
                    <Prefix>folder1/file</Prefix>
                    <KeyCount>0</KeyCount>
                    <MaxKeys>1000</MaxKeys>
                    <IsTruncated>false</IsTruncated>
                </ListBucketResult>
                """,
                Dict("Bucket" => "bucket-2", "prefix" => "file") =>
                """
                <?xml version="1.0" encoding="utf-8"?>
                <ListBucketResult xmlns="http://s3.amazonaws.com/doc/2006-03-01/">
                    <Name>bucket-2</Name>
                    <Prefix>file</Prefix>
                    <KeyCount>0</KeyCount>
                    <MaxKeys>1000</MaxKeys>
                    <IsTruncated>false</IsTruncated>
                </ListBucketResult>
                """,
            )
            return results[args]
        end
    ),
    3 => (
        @patch function list_objects_v2(config::AWSConfig, args)
            results = Dict(
                Dict("Bucket" => "bucket-1", "prefix" => "dir1/") =>
                """
                <?xml version="1.0" encoding="utf-8"?>
                <ListBucketResult xmlns="http://s3.amazonaws.com/doc/2006-03-01/">
                    <Name></Name>
                    <Prefix>dir1/</Prefix>
                    <KeyCount>2</KeyCount>
                    <MaxKeys>1000</MaxKeys>
                    <IsTruncated>false</IsTruncated>
                    <Contents>
                      <Key>dir1/file</Key>
                      <LastModified>2018-06-27T15:19:55.000Z</LastModified>
                      <Size>12</Size>
                    </Contents>
                    <Contents>
                      <Key>dir1/folder1/file</Key>
                      <LastModified>2018-06-27T15:19:55.000Z</LastModified>
                      <Size>4</Size>
                    </Contents>
                </ListBucketResult>
                """,
                Dict("Bucket" => "bucket-1", "prefix" => "dir1/folder1/file") =>
                """
                <?xml version="1.0" encoding="utf-8"?>
                <ListBucketResult xmlns="http://s3.amazonaws.com/doc/2006-03-01/">
                    <Name></Name>
                    <Prefix>dir1/folder1/file</Prefix>
                    <KeyCount>1</KeyCount>
                    <MaxKeys>1000</MaxKeys>
                    <IsTruncated>false</IsTruncated>
                    <Contents>
                      <Key>dir1/folder1/file</Key>
                      <LastModified>2018-06-27T15:19:55.000Z</LastModified>
                      <Size>4</Size>
                    </Contents>
                </ListBucketResult>
                """,
                Dict("Bucket" => "bucket-1", "prefix" => "dir1/file") =>
                """
                <?xml version="1.0" encoding="utf-8"?>
                <ListBucketResult xmlns="http://s3.amazonaws.com/doc/2006-03-01/">
                    <Name></Name>
                    <Prefix>dir1/file</Prefix>
                    <KeyCount>1</KeyCount>
                    <MaxKeys>1000</MaxKeys>
                    <IsTruncated>false</IsTruncated>
                    <Contents>
                      <Key>dir1/file</Key>
                      <LastModified>2018-06-27T15:19:55.000Z</LastModified>
                      <Size>12</Size>
                    </Contents>
                </ListBucketResult>
                """,
                Dict("Bucket" => "bucket-1", "prefix" => "dir2/") =>
                """
                <?xml version="1.0" encoding="utf-8"?>
                <ListBucketResult xmlns="http://s3.amazonaws.com/doc/2006-03-01/">
                    <Name></Name>
                    <Prefix>dir2/</Prefix>
                    <KeyCount>1</KeyCount>
                    <MaxKeys>1000</MaxKeys>
                    <IsTruncated>false</IsTruncated>
                    <Contents>
                      <Key>dir2/folder2/file2</Key>
                      <LastModified>2018-06-27T15:19:55.000Z</LastModified>
                      <Size>4</Size>
                    </Contents>
                </ListBucketResult>
                """,
                Dict("Bucket" => "bucket-1", "prefix" => "dir2/folder1/file") =>
                """
                <?xml version="1.0" encoding="utf-8"?>
                <ListBucketResult xmlns="http://s3.amazonaws.com/doc/2006-03-01/">
                    <Name>bucket-2</Name>
                    <Prefix>dir2/folder1/file</Prefix>
                    <KeyCount>0</KeyCount>
                    <MaxKeys>1000</MaxKeys>
                    <IsTruncated>false</IsTruncated>
                </ListBucketResult>
                """,
                Dict("Bucket" => "bucket-1", "prefix" => "dir2/file") =>
                """
                <?xml version="1.0" encoding="utf-8"?>
                <ListBucketResult xmlns="http://s3.amazonaws.com/doc/2006-03-01/">
                    <Name>bucket-2</Name>
                    <Prefix>dir2/file</Prefix>
                    <KeyCount>0</KeyCount>
                    <MaxKeys>1000</MaxKeys>
                    <IsTruncated>false</IsTruncated>
                </ListBucketResult>
                """,
                Dict("Bucket" => "bucket-1", "prefix" => "dir2/folder2/file2") =>
                """
                <?xml version="1.0" encoding="utf-8"?>
                <ListBucketResult xmlns="http://s3.amazonaws.com/doc/2006-03-01/">
                    <Name>bucket-2</Name>
                    <Prefix>dir2/folder2/file2</Prefix>
                    <KeyCount>1</KeyCount>
                    <MaxKeys>1000</MaxKeys>
                    <IsTruncated>false</IsTruncated>
                    <Contents>
                      <Key>dir2/folder2/file2</Key>
                      <LastModified>2018-06-27T15:19:55.000Z</LastModified>
                      <Size>4</Size>
                    </Contents>
                </ListBucketResult>
                """,
            )
            return results[args]
        end
    ),
    4 => (
        @patch function list_objects_v2(config::AWSConfig, args)
            results = Dict(
                Dict("Bucket" => "bucket-1", "prefix" => "dir1/") =>
                """
                <?xml version="1.0" encoding="utf-8"?>
                <ListBucketResult xmlns="http://s3.amazonaws.com/doc/2006-03-01/">
                    <Name></Name>
                    <Prefix>dir1/</Prefix>
                    <KeyCount>2</KeyCount>
                    <MaxKeys>1000</MaxKeys>
                    <IsTruncated>false</IsTruncated>
                    <Contents>
                      <Key>dir1/file</Key>
                      <LastModified>2018-06-27T15:19:55.000Z</LastModified>
                      <Size>12</Size>
                    </Contents>
                    <Contents>
                      <Key>dir1/folder1/file</Key>
                      <LastModified>2018-06-27T15:19:55.000Z</LastModified>
                      <Size>4</Size>
                    </Contents>
                </ListBucketResult>
                """,
                Dict("Bucket" => "bucket-1", "prefix" => "dir1/folder1/file") =>
                """
                <?xml version="1.0" encoding="utf-8"?>
                <ListBucketResult xmlns="http://s3.amazonaws.com/doc/2006-03-01/">
                    <Name></Name>
                    <Prefix>dir1/folder1/file</Prefix>
                    <KeyCount>1</KeyCount>
                    <MaxKeys>1000</MaxKeys>
                    <IsTruncated>false</IsTruncated>
                    <Contents>
                      <Key>dir1/folder1/file</Key>
                      <LastModified>2018-06-27T15:19:55.000Z</LastModified>
                      <Size>4</Size>
                    </Contents>
                </ListBucketResult>
                """,
                Dict("Bucket" => "bucket-1", "prefix" => "dir1/file") =>
                """
                <?xml version="1.0" encoding="utf-8"?>
                <ListBucketResult xmlns="http://s3.amazonaws.com/doc/2006-03-01/">
                    <Name></Name>
                    <Prefix>dir1/file</Prefix>
                    <KeyCount>1</KeyCount>
                    <MaxKeys>1000</MaxKeys>
                    <IsTruncated>false</IsTruncated>
                    <Contents>
                      <Key>dir1/file</Key>
                      <LastModified>2018-06-27T15:19:55.000Z</LastModified>
                      <Size>12</Size>
                    </Contents>
                </ListBucketResult>
                """,
                Dict("Bucket" => "bucket-2", "prefix" => "dir2/") =>
                """
                <?xml version="1.0" encoding="utf-8"?>
                <ListBucketResult xmlns="http://s3.amazonaws.com/doc/2006-03-01/">
                    <Name></Name>
                    <Prefix>dir2/</Prefix>
                    <KeyCount>1</KeyCount>
                    <MaxKeys>1000</MaxKeys>
                    <IsTruncated>false</IsTruncated>
                    <Contents>
                      <Key>dir2/file2</Key>
                      <LastModified>2018-06-27T15:19:55.000Z</LastModified>
                      <Size>12</Size>
                    </Contents>
                </ListBucketResult>
                """,
                Dict("Bucket" => "bucket-2", "prefix" => "dir2/folder1/file") =>
                """
                <?xml version="1.0" encoding="utf-8"?>
                <ListBucketResult xmlns="http://s3.amazonaws.com/doc/2006-03-01/">
                    <Name>bucket-2</Name>
                    <Prefix>dir2/folder1/file</Prefix>
                    <KeyCount>0</KeyCount>
                    <MaxKeys>1000</MaxKeys>
                    <IsTruncated>false</IsTruncated>
                </ListBucketResult>
                """,
                Dict("Bucket" => "bucket-2", "prefix" => "dir2/file") =>
                """
                <?xml version="1.0" encoding="utf-8"?>
                <ListBucketResult xmlns="http://s3.amazonaws.com/doc/2006-03-01/">
                    <Name>bucket-2</Name>
                    <Prefix>dir2/file</Prefix>
                    <KeyCount>0</KeyCount>
                    <MaxKeys>1000</MaxKeys>
                    <IsTruncated>false</IsTruncated>
                </ListBucketResult>
                """,
                Dict("Bucket" => "bucket-2", "prefix" => "dir2/file2") =>
                """
                <?xml version="1.0" encoding="utf-8"?>
                <ListBucketResult xmlns="http://s3.amazonaws.com/doc/2006-03-01/">
                    <Name>bucket-2</Name>
                    <Prefix>dir2/file2/file</Prefix>
                    <KeyCount>1</KeyCount>
                    <MaxKeys>1000</MaxKeys>
                    <IsTruncated>false</IsTruncated>
                    <Contents>
                      <Key>dir2/file2</Key>
                      <LastModified>2018-06-27T15:19:55.000Z</LastModified>
                      <Size>12</Size>
                    </Contents>
                </ListBucketResult>
                """,
            )

            return results[args]
        end
    ),
    5 => (
        @patch function list_objects_v2(config::AWSConfig, args)
            results = Dict(
                Dict("Bucket" => "bucket-1", "prefix" => "") =>
                """
                <?xml version="1.0" encoding="utf-8"?>
                <ListBucketResult xmlns="http://s3.amazonaws.com/doc/2006-03-01/">
                    <Name></Name>
                    <Prefix/>
                    <KeyCount>3</KeyCount>
                    <MaxKeys>1000</MaxKeys>
                    <IsTruncated>false</IsTruncated>
                    <Contents>
                      <Key>file1</Key>
                      <LastModified>2018-06-27T15:19:55.000Z</LastModified>
                      <Size>12</Size>
                    </Contents>
                    <Contents>
                      <Key>file2</Key>
                      <LastModified>2018-06-27T15:19:55.000Z</LastModified>
                      <Size>0</Size>
                    </Contents>
                    <Contents>
                      <Key>folder1/file3</Key>
                      <LastModified>2018-06-27T15:19:55.000Z</LastModified>
                      <Size>4</Size>
                    </Contents>
                </ListBucketResult>
                """,
                Dict("Bucket" => "bucket-1", "prefix" => "folder1/file3") =>
                """
                <?xml version="1.0" encoding="utf-8"?>
                <ListBucketResult xmlns="http://s3.amazonaws.com/doc/2006-03-01/">
                    <Name></Name>
                    <Prefix>folder1/file3</Prefix>
                    <KeyCount>1</KeyCount>
                    <MaxKeys>1000</MaxKeys>
                    <IsTruncated>false</IsTruncated>
                    <Contents>
                      <Key>folder1/file3</Key>
                      <LastModified>2018-06-27T15:19:55.000Z</LastModified>
                      <Size>4</Size>
                    </Contents>
                </ListBucketResult>
                """,
                Dict("Bucket" => "bucket-1", "prefix" => "file1") =>
                """
                <?xml version="1.0" encoding="utf-8"?>
                <ListBucketResult xmlns="http://s3.amazonaws.com/doc/2006-03-01/">
                    <Name></Name>
                    <Prefix>file1</Prefix>
                    <KeyCount>1</KeyCount>
                    <MaxKeys>1000</MaxKeys>
                    <IsTruncated>false</IsTruncated>
                    <Contents>
                      <Key>file1</Key>
                      <LastModified>2018-06-27T15:19:55.000Z</LastModified>
                      <Size>12</Size>
                    </Contents>
                </ListBucketResult>
                """,
                Dict("Bucket" => "bucket-1", "prefix" => "file2") =>
                """
                <?xml version="1.0" encoding="utf-8"?>
                <ListBucketResult xmlns="http://s3.amazonaws.com/doc/2006-03-01/">
                    <Name></Name>
                    <Prefix>file2</Prefix>
                    <KeyCount>1</KeyCount>
                    <MaxKeys>1000</MaxKeys>
                    <IsTruncated>false</IsTruncated>
                    <Contents>
                      <Key>file2</Key>
                      <LastModified>2018-06-27T15:19:55.000Z</LastModified>
                      <Size>0</Size>
                    </Contents>
                </ListBucketResult>
                """,
                Dict("Bucket" => "bucket-2", "prefix" => "dir2/") =>
                """
                <?xml version="1.0" encoding="utf-8"?>
                <ListBucketResult xmlns="http://s3.amazonaws.com/doc/2006-03-01/">
                    <Name></Name>
                    <Prefix>dir2/</Prefix>
                    <KeyCount>2</KeyCount>
                    <MaxKeys>1000</MaxKeys>
                    <IsTruncated>false</IsTruncated>
                    <Contents>
                      <Key>dir2/file2</Key>
                      <LastModified>2018-06-27T15:19:55.000Z</LastModified>
                      <Size>12</Size>
                    </Contents>
                    <Contents>
                      <Key>dir2/folder2/file3</Key>
                      <LastModified>2018-06-27T15:19:55.000Z</LastModified>
                      <Size>4</Size>
                    </Contents>
                </ListBucketResult>
                """,
                Dict("Bucket" => "bucket-2", "prefix" => "dir2/folder1/file3") =>
                """
                <?xml version="1.0" encoding="utf-8"?>
                <ListBucketResult xmlns="http://s3.amazonaws.com/doc/2006-03-01/">
                    <Name>bucket-2</Name>
                    <Prefix>dir2/folder1/file3</Prefix>
                    <KeyCount>0</KeyCount>
                    <MaxKeys>1000</MaxKeys>
                    <IsTruncated>false</IsTruncated>
                </ListBucketResult>
                """,
                Dict("Bucket" => "bucket-2", "prefix" => "dir2/file1") =>
                """
                <?xml version="1.0" encoding="utf-8"?>
                <ListBucketResult xmlns="http://s3.amazonaws.com/doc/2006-03-01/">
                    <Name>bucket-2</Name>
                    <Prefix>dir2/file1</Prefix>
                    <KeyCount>0</KeyCount>
                    <MaxKeys>1000</MaxKeys>
                    <IsTruncated>false</IsTruncated>
                </ListBucketResult>
                """,
                Dict("Bucket" => "bucket-2", "prefix" => "dir2/file2") =>
                """
                <?xml version="1.0" encoding="utf-8"?>
                <ListBucketResult xmlns="http://s3.amazonaws.com/doc/2006-03-01/">
                    <Name>bucket-2</Name>
                    <Prefix>dir2/file2</Prefix>
                    <KeyCount>1</KeyCount>
                    <MaxKeys>1000</MaxKeys>
                    <IsTruncated>false</IsTruncated>
                    <Contents>
                      <Key>dir2/file2</Key>
                      <LastModified>2018-06-27T15:19:55.000Z</LastModified>
                      <Size>12</Size>
                    </Contents>
                </ListBucketResult>
                """,
                Dict("Bucket" => "bucket-2", "prefix" => "dir2/folder2/file3") =>
                """
                <?xml version="1.0" encoding="utf-8"?>
                <ListBucketResult xmlns="http://s3.amazonaws.com/doc/2006-03-01/">
                    <Name>bucket-2</Name>
                    <Prefix>dir2/folder2/file3</Prefix>
                    <KeyCount>1</KeyCount>
                    <MaxKeys>1000</MaxKeys>
                    <IsTruncated>false</IsTruncated>
                    <Contents>
                      <Key>dir2/folder2/file3</Key>
                      <LastModified>2018-06-27T15:19:55.000Z</LastModified>
                      <Size>4</Size>
                    </Contents>
                </ListBucketResult>
                """,
            )
            return results[args]
        end
    ),
    6 => (
        @patch function list_objects_v2(config::AWSConfig, args)
            results = Dict(
                Dict("Bucket" => "bucket-1", "prefix" => "folder/file") =>
                """
                <?xml version="1.0" encoding="utf-8"?>
                <ListBucketResult xmlns="http://s3.amazonaws.com/doc/2006-03-01/">
                    <Name></Name>
                    <Prefix>folder/file</Prefix>
                    <KeyCount>0</KeyCount>
                    <MaxKeys>1000</MaxKeys>
                    <IsTruncated>false</IsTruncated>
                </ListBucketResult>
                """,
                Dict("Bucket" => "bucket-1", "prefix" => "file") =>
                """
                <?xml version="1.0" encoding="utf-8"?>
                <ListBucketResult xmlns="http://s3.amazonaws.com/doc/2006-03-01/">
                    <Name></Name>
                    <Prefix>file</Prefix>
                    <KeyCount>0</KeyCount>
                    <MaxKeys>1000</MaxKeys>
                    <IsTruncated>false</IsTruncated>
                </ListBucketResult>
                """,
                Dict("Bucket" => "bucket-1", "prefix" => "") =>
                """
                <?xml version="1.0" encoding="utf-8"?>
                <ListBucketResult xmlns="http://s3.amazonaws.com/doc/2006-03-01/">
                    <Name></Name>
                    <Prefix/>
                    <KeyCount>3</KeyCount>
                    <MaxKeys>1000</MaxKeys>
                    <IsTruncated>false</IsTruncated>
                    <Contents>
                      <Key>file1</Key>
                      <LastModified>2018-06-27T15:19:55.000Z</LastModified>
                      <Size>12</Size>
                    </Contents>
                    <Contents>
                      <Key>file2</Key>
                      <LastModified>2018-06-27T15:19:55.000Z</LastModified>
                      <Size>0</Size>
                    </Contents>
                    <Contents>
                      <Key>folder1/file3</Key>
                      <LastModified>2018-06-27T15:19:55.000Z</LastModified>
                      <Size>4</Size>
                    </Contents>
                </ListBucketResult>
                """,
                Dict("Bucket" => "bucket-1", "prefix" => "folder1/file3") =>
                """
                <?xml version="1.0" encoding="utf-8"?>
                <ListBucketResult xmlns="http://s3.amazonaws.com/doc/2006-03-01/">
                    <Name></Name>
                    <Prefix>folder1/file3</Prefix>
                    <KeyCount>1</KeyCount>
                    <MaxKeys>1000</MaxKeys>
                    <IsTruncated>false</IsTruncated>
                    <Contents>
                      <Key>folder1/file3</Key>
                      <LastModified>2018-06-27T15:19:55.000Z</LastModified>
                      <Size>4</Size>
                    </Contents>
                </ListBucketResult>
                """,
                Dict("Bucket" => "bucket-1", "prefix" => "file1") =>
                """
                <?xml version="1.0" encoding="utf-8"?>
                <ListBucketResult xmlns="http://s3.amazonaws.com/doc/2006-03-01/">
                    <Name></Name>
                    <Prefix>file1</Prefix>
                    <KeyCount>1</KeyCount>
                    <MaxKeys>1000</MaxKeys>
                    <IsTruncated>false</IsTruncated>
                    <Contents>
                      <Key>file1</Key>
                      <LastModified>2018-06-27T15:19:55.000Z</LastModified>
                      <Size>12</Size>
                    </Contents>
                </ListBucketResult>
                """,
                Dict("Bucket" => "bucket-1", "prefix" => "file2") =>
                """
                <?xml version="1.0" encoding="utf-8"?>
                <ListBucketResult xmlns="http://s3.amazonaws.com/doc/2006-03-01/">
                    <Name></Name>
                    <Prefix>file2</Prefix>
                    <KeyCount>1</KeyCount>
                    <MaxKeys>1000</MaxKeys>
                    <IsTruncated>false</IsTruncated>
                    <Contents>
                      <Key>file2</Key>
                      <LastModified>2018-06-27T15:19:55.000Z</LastModified>
                      <Size>0</Size>
                    </Contents>
                </ListBucketResult>
                """,
            )
            return results[args]
        end
    ),
    7 => (
        @patch function list_objects_v2(config::AWSConfig, args)
            results = Dict(
                Dict("Bucket" => "bucket-1", "prefix" => "") =>
                """
                <?xml version="1.0" encoding="utf-8"?>
                <ListBucketResult xmlns="http://s3.amazonaws.com/doc/2006-03-01/">
                    <Name></Name>
                    <Prefix/>
                    <KeyCount>3</KeyCount>
                    <MaxKeys>1000</MaxKeys>
                    <IsTruncated>false</IsTruncated>
                    <Contents>
                      <Key>file1</Key>
                      <LastModified>2018-06-27T15:19:55.000Z</LastModified>
                      <Size>12</Size>
                    </Contents>
                    <Contents>
                      <Key>file2</Key>
                      <LastModified>2018-06-27T15:19:55.000Z</LastModified>
                      <Size>0</Size>
                    </Contents>
                    <Contents>
                      <Key>folder1/file3</Key>
                      <LastModified>2018-06-27T15:19:55.000Z</LastModified>
                      <Size>4</Size>
                    </Contents>
                </ListBucketResult>
                """,
                Dict("Bucket" => "bucket-1", "prefix" => "folder1/file3") =>
                """
                <?xml version="1.0" encoding="utf-8"?>
                <ListBucketResult xmlns="http://s3.amazonaws.com/doc/2006-03-01/">
                    <Name></Name>
                    <Prefix>folder1/file3</Prefix>
                    <KeyCount>1</KeyCount>
                    <MaxKeys>1000</MaxKeys>
                    <IsTruncated>false</IsTruncated>
                    <Contents>
                      <Key>folder1/file3</Key>
                      <LastModified>2018-06-27T15:19:55.000Z</LastModified>
                      <Size>4</Size>
                    </Contents>
                </ListBucketResult>
                """,
                Dict("Bucket" => "bucket-1", "prefix" => "file1") =>
                """
                <?xml version="1.0" encoding="utf-8"?>
                <ListBucketResult xmlns="http://s3.amazonaws.com/doc/2006-03-01/">
                    <Name></Name>
                    <Prefix>file1</Prefix>
                    <KeyCount>1</KeyCount>
                    <MaxKeys>1000</MaxKeys>
                    <IsTruncated>false</IsTruncated>
                    <Contents>
                      <Key>file1</Key>
                      <LastModified>2018-06-27T15:19:55.000Z</LastModified>
                      <Size>12</Size>
                    </Contents>
                </ListBucketResult>
                """,
                Dict("Bucket" => "bucket-1", "prefix" => "file2") =>
                """
                <?xml version="1.0" encoding="utf-8"?>
                <ListBucketResult xmlns="http://s3.amazonaws.com/doc/2006-03-01/">
                    <Name></Name>
                    <Prefix>file2</Prefix>
                    <KeyCount>1</KeyCount>
                    <MaxKeys>1000</MaxKeys>
                    <IsTruncated>false</IsTruncated>
                    <Contents>
                      <Key>file2</Key>
                      <LastModified>2018-06-27T15:19:55.000Z</LastModified>
                      <Size>0</Size>
                    </Contents>
                </ListBucketResult>
                """,
            )
            return results[args]
        end
    ),
    8 => (
        @patch function list_objects_v2(config::AWSConfig, args)
            results = Dict(
                Dict("Bucket" => "bucket", "prefix" => "test_file") =>
                """
                <?xml version="1.0" encoding="utf-8"?>
                <ListBucketResult xmlns="http://s3.amazonaws.com/doc/2006-03-01/">
                    <Name></Name>
                    <Prefix>test_file</Prefix>
                    <KeyCount>1</KeyCount>
                    <MaxKeys>1000</MaxKeys>
                    <IsTruncated>false</IsTruncated>
                    <Contents>
                      <Key>test_file</Key>
                      <LastModified>2018-06-27T15:19:55.000Z</LastModified>
                      <Size>0</Size>
                    </Contents>
                </ListBucketResult>
                """,
            )
            return results[args]
        end
    ),
)





