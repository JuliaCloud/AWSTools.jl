module CloudFormation

using AWSSDK
using Mocking
using XMLDict
using DataStructures: OrderedDict

using AWSSDK.CloudFormation: describe_stacks

export stack_description, stack_output

"""
    stack_description(stack_name::AbstractString) -> AbstractDict

Returns the description for the specified stack.
"""
function stack_description(stack_name::AbstractString)
    response = xml_dict(@mock describe_stacks(Dict("StackName" => stack_name)))
    return response["DescribeStacksResponse"]["DescribeStacksResult"]["Stacks"]["member"]
end

"""
    stack_output(stack_name::AbstractString) -> OrderedDict

The stack's OutputKey and OutputValue values as a dictionary.
"""
function stack_output(stack_name::AbstractString)
    outputs = OrderedDict{String, String}()
    description = stack_description(stack_name)

    if "Outputs" in keys(description)
        stack_outputs = description["Outputs"]["member"]

        if isa(stack_outputs, OrderedDict) # Only 1 stack output
            outputs[stack_outputs["OutputKey"]] = stack_outputs["OutputValue"]
        else
            for item in stack_outputs # More than 1 stack output
                outputs[item["OutputKey"]] = item["OutputValue"]
            end
        end
    end

    return outputs
end

end  # CloudFormation
