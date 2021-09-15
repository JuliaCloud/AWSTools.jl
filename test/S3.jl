using AWSTools
using FilePathsBase
using UUIDs

using AWSTools.CloudFormation: stack_output
using AWSTools.S3: sync, upload
using AWSS3: AWSS3, s3_create_bucket, s3_put, s3_delete_bucket

# Enables the running of the "batch" online tests. e.g ONLINE=batch
const ONLINE = strip.(split(get(ENV, "ONLINE", ""), r"\s*,\s*"))

# Run the online S3 tests on the bucket specified
const TEST_BUCKET_AND_PREFIX = let
    p = if haskey(ENV, "TEST_BUCKET_AND_PREFIX")
        ENV["TEST_BUCKET_AND_PREFIX"]
    elseif haskey(ENV, "AWS_STACKNAME")
        output = stack_output(ENV["AWS_STACKNAME"])

        if haskey(output, "TestBucketAndPrefix")
            "s3://" * output["TestBucketAndPrefix"] * "/AWSTools.jl"
        else
            nothing
        end
    else
        nothing
    end

    p !== nothing ? rstrip(p, '/') : p
end


function compare(src_file::AbstractPath, dest_file::AbstractPath)
    if isdir(src_file)
        @test isdir(dest_file)
        @test basename(src_file) == basename(dest_file)
    else
        @test isfile(src_file)
        @test isfile(dest_file)
        @test basename(dest_file) == basename(src_file)
        @test filesize(dest_file) == filesize(src_file)
        @test modified(dest_file) >= modified(src_file)

        # Test file contents are equal
        @test read(dest_file) == read(src_file)
    end
end

function compare_dir(src_dir::AbstractPath, dest_dir::AbstractPath)
    @test isdir(dest_dir)

    src_contents = collect(walkpath(src_dir))
    dest_contents = collect(walkpath(dest_dir))

    for (src, dst) in zip(src_contents, dest_contents)
        compare(src, dst)
    end
end

function bucket_and_key(s3_path::AbstractString)
    m = match(r"^s3://(?<bucket>[^/]++)/?+(?<key>.*)$", s3_path)

    if m !== nothing
        return m[:bucket], m[:key]
    else
        throw(ArgumentError("String is not an S3 path: \"$s3_path\""))
    end
end


@testset "S3" begin
    @testset "presign" begin
        @testset "minimum period" begin
            @test_throws InexactError AWSTools.S3.presign(
                p"s3://bucket/file",
                Dates.Millisecond(999),
            )
        end
    end

    @testset "Syncing" begin
        # Create files to sync
        mktmpdir() do src
            src_file = join(src, "file1")
            write(src_file, "Hello World!")

            src_folder = join(src, "folder1")
            mkdir(src_folder)
            src_folder_file = join(src_folder, "file2")
            write(src_folder_file, "") # empty file

            src_folder2 = join(src_folder, "folder2") # nested folders
            mkdir(src_folder2)
            src_folder2_file = join(src_folder2, "file3")
            write(src_folder2_file, "Test")

            # Sync files
            mktmpdir() do dest
                @test isdir(dest)
                @test_deprecated sync(string(src), string(dest))

                # Test directories are the same
                compare_dir(src, dest)
            end
        end
    end

    if "S3" in ONLINE
        @testset "Online" begin
            @info "Running ONLINE S3 tests"

            # Create bucket for tests
            test_run_id = string(uuid4())
            s3_prefix = if TEST_BUCKET_AND_PREFIX === nothing
                bucket = string("awstools-s3-test-temp-", uuid4())
                @info "Creating S3 bucket $bucket"
                s3_create_bucket(bucket)
                "s3://$bucket/$test_run_id"
            else
                "$TEST_BUCKET_AND_PREFIX/$test_run_id"
            end

            try
                @testset "Upload to S3" begin
                    dest = @test_deprecated S3Path("$s3_prefix/folder3/testfile")

                    try
                        mktemp() do src, stream
                            write(stream, "Local file src")
                            close(stream)

                            @test !exists(dest)

                            uploaded_file = @test_deprecated upload(Path(src), dest)
                            @test isa(uploaded_file, S3Path)

                            @test exists(dest)
                            @test isfile(dest)
                            @test isdir(parent(dest))
                            @test read(dest, String) == "Local file src"
                        end
                    finally
                        rm(dest; recursive=true)
                    end
                end

                @testset "Download via presign" begin
                    src = S3Path("$s3_prefix/presign/file")
                    content = "presigned content"
                    s3_put(src.bucket, src.key, content)

                    @testset "file" begin
                        url = @test_deprecated AWSTools.S3.presign(src, Dates.Minute(1))
                        r = HTTP.get(url)
                        @test String(r.body) == content
                    end
                end

            finally
                # Clean up any files left in the test directory
                rm(S3Path("$s3_prefix/"); recursive=true)

                # Delete bucket if it was explicitly created
                if TEST_BUCKET_AND_PREFIX === nothing
                    s3_bucket_dir = replace(s3_prefix, r"^(s3://[^/]+).*$" => s"\1")
                    bucket, key = bucket_and_key(s3_bucket_dir)
                    @info "Deleting S3 bucket $bucket"
                    rm(S3Path("s3://$bucket/"); recursive=true)
                    s3_delete_bucket(bucket)
                end
            end
        end
    else
        @warn """
            Skipping AWSTools.S3 ONLINE tests. Set `ENV["ONLINE"] = "S3"` to run."
            Can also optionally specify a test bucket name `ENV["TEST_BUCKET_AND_PREFIX"] = "s3://bucket/dir/"`.
            If `TEST_BUCKET_AND_PREFIX` is not specified, a temporary bucket will be created, used, and then deleted.
            """
    end
end
