using Dates
using AWSS3

"""
    upload(src::AbstractPath, dest::S3Path)

Uploads a local file to the s3 path specified by `dest`.
"""
upload

const upload = Base.cp

# Note: naming copied from Go SDK:
# https://docs.aws.amazon.com/sdk-for-go/v1/developer-guide/s3-example-presigned-urls.html
function presign(
    path::S3Path,
    duration::Period=Hour(1);
    config::AWSConfig=aws_config(),
)
    AWSS3.s3_sign_url(config, path.bucket, path.key, Dates.value(Second(duration)))
end
