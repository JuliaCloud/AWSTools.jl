module EC2

using ...AWSTools: timeout
using HTTP: HTTP
using Mocking

export instance_metadata, instance_region, instance_availability_zone

"""
    instance_metadata(path) -> Union{String,Nothing}

Retrieve AWS EC2 instance metadata as a string from the provided `path`. If no instance
metadata is available (typically due to not running within an EC2 instance) then `nothing`
will be returned. See the AWS documentation for details on what metadata is available.

https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/ec2-instance-metadata.html
"""
function instance_metadata(path::AbstractString)
    # Retrieve details about the instance:
    # https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/ec2-instance-metadata.html
    #
    # Note: When running outside of EC2 the connection to the local-link address will fail
    # with a connection timeout (ETIMEDOUT) after a 60 seconds (tested on HTTP.jl v0.8.2)
    # See: https://github.com/JuliaWeb/HTTP.jl/issues/114
    uri = HTTP.URI(scheme="http", host="169.254.169.254", path=path)

    r = timeout(5) do
        # Work around for Mocking: https://github.com/invenia/Mocking.jl/issues/16
        http_get = HTTP.get
        @mock http_get(uri, status_exception=false)
    end

    return r !== nothing ? String(something(r).body) : r
end

"""
    instance_availability_zone() -> Union{String,Nothing}

Get the availability zone of the host if running inside of an EC2 instance. If not running
within an EC2 instance `nothing` is returned.
"""
function instance_availability_zone()
    # Get the availability zone information from the EC2 instance metadata.
    return instance_metadata("/latest/meta-data/placement/availability-zone")
end

"""
    instance_availability_zone() -> Union{String,Nothing}

Get the region of the host if executed inside of an EC2 instance. If not running within an
EC2 instance `nothing` is returned.
"""
instance_region() = chop(instance_availability_zone())

end
