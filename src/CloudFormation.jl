module CloudFormation

using AWSCore
using AWSCore.Services: cloudformation
using DataStructures: OrderedDict
using MbedTLS: MbedException
using Memento
using Mocking
using XMLDict

const logger = getlogger(@__MODULE__)

# Register the module level logger at runtime so that folks can access the logger via `getlogger(MyModule)`
# NOTE: If this line is not included then the precompiled `MyModule.logger` won't be registered at runtime.
__init__() = Memento.register(logger)

export stack_description, stack_output

describe_stacks(config; kwargs...) = cloudformation(config, "DescribeStacks"; kwargs...)


const _NRETRIES = 3
# for APIs we don't want to hammer
function minimal_delays(; kwargs...)
    return ExponentialBackOff(; n=_NRETRIES, first_delay=0.1, max_delay=60, kwargs...)
end


"""
    stack_description(stack_name::AbstractString) -> AbstractDict

Returns the description for the specified stack. Can optionally pass in the aws `config`
as a keyword argument.
"""
function stack_description(
    stack_name::AbstractString;
    config::AWSConfig=default_aws_config()
)
    function retry_cond(s, e)
        if e isa AWSException
            if 500 <= e.cause.status <= 504
                debug(logger, "CloudFormation request encountered $(e.code); retrying")
                return (s, true)
            elseif e.cause.status == 429 || (e.cause.status == 400 && e.code == "Throttling")
                debug(logger, "CloudFormation request encountered $(e.code); retrying")
                return (s, true)
            end
        elseif e isa MbedException
            debug(logger, "CloudFormation request encountered $e; retrying")
            return (s, true)
        end

        return (s, false)
    end

    f = retry(delays=minimal_delays(), check=retry_cond) do
        @mock describe_stacks(config, StackName=stack_name)
    end

    response = xml_dict(f())

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
