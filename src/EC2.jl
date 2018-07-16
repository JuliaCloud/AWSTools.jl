module EC2

using Mocking

"""
    instance_availability_zone() -> String

Get the availability zone of the host if running inside of an EC2 instance.
"""
function instance_availability_zone()
    # Get the availability zone information from the EC2 instance metadata.
    @mock readstring(pipeline(`curl http://169.254.169.254/latest/meta-data/placement/availability-zone`; stderr=DevNull))
end

"""
    instance_availability_zone() -> String

Get the region of the host if executed inside of an EC2 instance.
"""
instance_region() = chop(instance_availability_zone())

end