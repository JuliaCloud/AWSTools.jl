using AWS
using Base: CmdRedirect
using Base64
using Dates: datetime2unix, now

const invalid_access_key = "ThisIsMyInvalidAccessKey"
const invalid_secret_key = "ThisIsMyInvalidSecretKey"

function get_auth(config::AWSConfig; params::AbstractDict=Dict())
    id = lpad(!haskey(params, "registryIds") ? "" : first(params["registryIds"]), 12, '0')
    return Dict(
        "authorizationData" => [
            Dict(
                "authorizationToken" => base64encode("AWS:password"),
                "proxyEndpoint" => "https://$(id).dkr.ecr.us-east-1.amazonaws.com",
            ),
        ],
    )
end

get_caller_identity_patch = @patch function AWSTools.get_caller_identity()
    account_id = join(rand(0:9, 12), "")
    return Dict(
        "GetCallerIdentityResult" => Dict(
            Dict(
                "Account" => account_id,
                "Arn" => "arn:aws:iam::$account_id:user/UserName",
                "UserId" => join(rand('A':'Z', 21), ""),
            ),
        ),
    )
end
sts_assume_role = @patch function AWSTools.STS.assume_role(
    role_arn, role_session_name; aws_config
)
    return Dict(
        "AssumeRoleResult" => Dict(
            "Credentials" => Dict(
                "AccessKeyId" => "TESTACCESSKEYID",
                "SecretAccessKey" => "TESTSECRETACEESSKEY",
                "SessionToken" => "TestSessionToken",
                "Expiration" => "2021-11-03T16:37:10Z",
            ),
        ),
    )
end

function instance_metadata_patch(result)
    @patch HTTP.get(args...; kwargs...) = result
end

get_authorization_token_patch = @patch function AWSTools.ECR.get_authorization_token(
    config::AWSConfig, params::AbstractDict
)
    return get_auth(config; params=params)
end

get_authorization_token_no_param_patch = @patch function AWSTools.ECR.get_authorization_token(
    config::AWSConfig
)
    return get_auth(config)
end
describe_stacks_patch = @patch function AWSTools.CloudFormation.describe_stacks(
    config, params
)
    responses = Dict(
        Dict("StackName" => "stackname", "return_raw" => true) => """
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
        Dict("StackName" => "1-stack-output-stackname", "return_raw" => true) => """
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
        Dict("StackName" => "multiple-stack-outputs-stackname", "return_raw" => true) => """
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
        Dict("StackName" => "empty-value", "return_raw" => true) => """
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
        Dict("StackName" => "export", "return_raw" => true) => """
                                                               <DescribeStacksResponse xmlns="http://cloudformation.amazonaws.com/doc/2010-05-15/">
                                                                 <DescribeStacksResult>
                                                                   <Stacks>
                                                                     <member>
                                                                       <Outputs>
                                                                         <member>
                                                                           <Description>Exported output for use in other stacks</Description>
                                                                           <ExportName>ExportedKey</ExportName>
                                                                           <OutputKey>Key</OutputKey>
                                                                           <OutputValue>Value</OutputValue>
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

    # So we can test that we get an error using the invalid access and secret keys
    access_key = config.credentials.access_key_id
    secret_key = config.credentials.secret_key
    if access_key == invalid_access_key && secret_key == invalid_secret_key
        throw(
            AWSException(
                HTTP.StatusError(
                    403,
                    "",
                    "",
                    HTTP.Messages.Response(
                        403,
                        """
<ErrorResponse xmlns="http://cloudformation.amazonaws.com/doc/2010-05-15/">
    <Error>
    <Type>Sender</Type>
    <Code>InvalidClientTokenId</Code>
    <Message>The security token included in the request is invalid.</Message>
    </Error>
    <RequestId>cff5beb8-4b7b-11e9-9c2b-43c18f6078dc</RequestId>
</ErrorResponse>
""",
                    ),
                ),
            ),
        )
    else
        return responses[params]
    end
end

function throttle_patch(allow)
    describe_stacks_throttle_count = 0
    @patch function AWSTools.CloudFormation.describe_stacks(config, params)
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
            response = HTTP.Messages.Response(400, error_message)
            http_error = HTTP.ExceptionRequest.StatusError(400, "", "", response)
            throw(AWSException(http_error))
        end
        responses = Dict(
            Dict("StackName" => "stackname", "return_raw" => true) => """
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

        return responses[params]
    end
end
