module CloudFormation

using Mocking
using XMLDict

using AWSCore
using AWSSDK.CloudFormation: describe_stacks
using Compat: AbstractDict
using DataStructures: OrderedDict

export stack_description, stack_output

"""
    stack_description(stack_name::AbstractString) -> AbstractDict

Returns the description for the specified stack. Can optionally pass in the aws `config`
as a keyword argument.
"""
function stack_description(
    stack_name::AbstractString;
    config::AWSConfig=default_aws_config()
)
    response = xml_dict(@mock describe_stacks(config, Dict("StackName" => stack_name)))
    return response["DescribeStacksResponse"]["DescribeStacksResult"]["Stacks"]["member"]
end

"""
    stack_output(stack_name::AbstractString) -> OrderedDict

The stack's OutputKey and OutputValue values as a dictionary. Can pass in the aws `config`
as a keyword argument.
"""
function stack_output(stack_name::AbstractString; config::AWSConfig=default_aws_config())
    outputs = OrderedDict{String, String}()
    description = stack_description(stack_name; config=config)

    if "Outputs" in keys(description)
        stack_outputs = description["Outputs"]["member"]

        if isa(stack_outputs, AbstractDict)
            # Only 1 stack output
            push!(outputs, output_pair(stack_outputs))
        else
            # More than 1 stack output
            for item in stack_outputs
                push!(outputs, output_pair(item))
            end
        end
    end

    return outputs
end

function output_pair(item::AbstractDict)
    key = item["OutputKey"]::String
    value = if isa(item["OutputValue"], String)
        item["OutputValue"]::String
    elseif isa(item["OutputValue"], AbstractDict) && isempty(item["OutputValue"])
        ""
    else
        throw(ArgumentError("Unhandled output value: $(repr(item["OutputValue"]))"))
    end

    return key => value
end

end  # CloudFormation
