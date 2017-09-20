# Example script of how to work with AWS batch jobs using AWSTools.

using AWSTools
using Memento
Memento.config("info"; fmt="[{level} | {name}]: {msg}")

job = BatchJob(
    name="AWSToolTest",
    image="292522074875.dkr.ecr.us-east-1.amazonaws.com/aws-tools:latest",
    role="arn:aws:iam::292522074875:role/AWSBatchClusterManagerJobRole",
    definition="AWSTools",
    queue="Replatforming-Manager",
    vcpus=1,
    memory=1024,
    cmd=`julia -e 'println("Hello World!")'`,
    output=S3Results("AWSTools", "test"),
)

submit(job)
wait(job, [AWSTools.SUCCEEDED])
results = logs(job)