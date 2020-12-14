using AWSTools
using FilePathsBase
using UUIDs

using AWSTools.CloudFormation: stack_output
using AWSTools.S3: sync, upload
using AWSS3: AWSS3, S3Path, s3_create_bucket, s3_put, s3_delete_bucket

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
        @test size(dest_file) == size(src_file)
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
        @testset "Sync two local directories" begin
            # Create files to sync
            src = mktmpdir()
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
            dest = mktmpdir()
            @test isdir(dest)
            sync(src, dest)

            # Test directories are the same
            compare_dir(src, dest)

            # Get paths of new files
            dest_file = join(dest, "file1")
            dest_file_mtime = modified(dest_file)
            dest_folder = join(dest, basename(src_folder))
            dest_folder_file = join(dest_folder, "file2")
            dest_folder2 = join(dest_folder, basename(src_folder2))
            dest_folder2_file = join(dest_folder2, "file3")

            # Test that contents get copied over and size is equal
            compare(src_file, dest_file)
            compare(src_folder_file, dest_folder_file)
            compare(src_folder2_file, dest_folder2_file)

            compare_dir(src_folder, dest_folder)
            compare_dir(src_folder2, dest_folder2)

            @testset "Sync modified dest file" begin
                # Modify a file in dest
                write(dest_folder_file, "Modified in dest.")

                # Syncing overwrites the newer file in dest because it is of different size
                sync(src, dest)
                compare(src_folder_file, dest_folder_file)
            end

            @testset "Sync modified src file" begin
                 # Modify a file in src
                write(src_folder_file, "Modified in src.")

                # Test that syncing overwrites the modified file in dest
                sync(src, dest)
                compare(src_folder_file, dest_folder_file)

                # Test other files weren't updated
                @test modified(dest_file) == dest_file_mtime
            end

            @testset "Sync newer dest file" begin
                # This is the case because a newer file of the same size is usually the
                # result of an uploaded file always having a newer last_modified time.

                # Modify a file in dest
                write(dest_folder_file, "Modified in dest")

                # Test that syncing doesn't overwrite the newer file in dest
                sync(src, dest)
                @test read(dest_folder_file) != read(src_folder_file)
            end

            @testset "Sync incompatible types" begin
                @test_throws ArgumentError sync(src, dest_folder_file)
                @test_throws ArgumentError sync(src_folder_file, dest)
            end

            rm(src_file)

            @testset "Sync deleted file with no delete flag" begin
                # Syncing should not delete the file in the destination
                sync(src, dest)
                @test isfile(dest_file)
            end

            @testset "Sync deleted files with delete flag" begin
                # Test that syncing deletes the file in dest
                sync(src, dest; delete=true)
                @test !isfile(dest_file)

                rm(Path(src_folder2); recursive=true)

                @test isfile(dest_folder2_file)
                @test isdir(dest_folder2)

                sync(src, dest; delete=true)

                @test !isfile(dest_folder2_file)
                @test !isdir(dest_folder2)
                @test isdir(dest_folder)
            end

            @testset "Sync files" begin
                @test !isfile(dest_file)

                write(src_file, "Test")

                sync(src_file, dest_file)

                @test isfile(dest_file)
                compare(src_file, dest_file)
            end

            @testset "Sync empty directory" begin
                rm(src; recursive=true)

                @test_throws ArgumentError sync(src, dest, delete=true)
            end

            @testset "Sync non existent directories" begin
                isdir(src) && rm(src; recursive=true)
                isdir(dest) && rm(dest; recursive=true)

                # Test syncing creates non existent local directories
                @test_throws ArgumentError sync(src, dest)
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
                        dest = Path("$s3_prefix/folder3/testfile")

                        try
                            mktemp() do src, stream
                                write(stream, "Local file src")
                                close(stream)

                                @test !exists(dest)

                                uploaded_file = upload(Path(src), dest)
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

                    @testset "Download from S3" begin
                        src = Path("$s3_prefix/folder4/testfile")

                        try
                            s3_put(src.bucket, src.key, "Remote content")

                            @testset "Download to a directory" begin
                                mktempdir() do dest_dir
                                    dest = Path(dest_dir)

                                    dest_file = download(src, dest)
                                    @test isa(dest_file, AbstractPath)

                                    @test exists(Path(dest_file))
                                    @test read(dest_file, String) == "Remote content"
                                end
                            end

                            @testset "Download to a local file" begin
                                mktemp() do dest_file, stream
                                    dest = Path(dest_file)
                                    close(stream)

                                    dest_file = download(src, dest)
                                    @test isa(dest_file, AbstractPath)

                                    @test dest_file == dest
                                    @test read(dest, String) == "Remote content"
                                end
                            end

                        finally
                            rm(src; recursive=true)
                        end
                    end

                    @testset "Download via presign" begin
                        src = S3Path("$s3_prefix/presign/file")
                        content = "presigned content"
                        s3_put(src.bucket, src.key, content)

                        @testset "file" begin
                            url = AWSTools.S3.presign(src, Dates.Minute(1))
                            r = HTTP.get(url)
                            @test String(r.body) == content
                        end

                        @testset "directory" begin
                            url = AWSTools.S3.presign(parent(src), Dates.Minute(1))
                            r = HTTP.get(url, status_exception=false)
                            @test r.status == 404
                            @test occursin("The specified key does not exist.", String(r.body))
                        end

                        @testset "expired" begin
                            url = AWSTools.S3.presign(src, Dates.Second(1))
                            sleep(2)
                            r = HTTP.get(url, status_exception=false)
                            @test r.status == 403
                            @test occursin("Request has expired", String(r.body))
                        end
                    end

                    @testset "Sync S3 directories" begin
                        bucket, key_prefix = bucket_and_key(s3_prefix)

                        src_dir = Path("$s3_prefix/folder1/")
                        dest_dir = Path("$s3_prefix/folder2/")

                        # Directories should be empty, but just in case
                        # delete any pre-existing objects in the s3 bucket directories
                        rm(src_dir; recursive=true)
                        rm(dest_dir; recursive=true)

                        # Make the src S3 directory
                        mkdir(src_dir; recursive=true)
                        mkdir(dest_dir; recursive=true)

                        # Note: using `lstrip` for when `key_prefix` is empty
                        # We also include the "folder" objects in this list.
                        s3_objects = [
                            Dict(
                                "Bucket" => bucket,
                                "Key" => lstrip("$key_prefix/folder1/", '/'),
                                "Content" => "",
                            ),
                            Dict(
                                "Bucket" => bucket,
                                "Key" => lstrip("$key_prefix/folder1/folder/", '/'),
                                "Content" => "",
                            ),
                            Dict(
                                "Bucket" => bucket,
                                "Key" => lstrip("$key_prefix/folder1/file1", '/'),
                                "Content" => "Hello World!",
                            ),
                            Dict(
                                "Bucket" => bucket,
                                "Key" => lstrip("$key_prefix/folder1/file2", '/'),
                                "Content" => "",
                            ),
                            Dict(
                                "Bucket" => bucket,
                                "Key" => lstrip("$key_prefix/folder1/folder/file3", '/'),
                                "Content" => "Test",
                            ),
                        ]

                        # Set up the source s3 directory
                        for object in s3_objects
                            s3_put(object["Bucket"], object["Key"], object["Content"])
                        end

                        # Sync files passing in directories as strings
                        sync(string(src_dir), string(dest_dir))

                        src_files = collect(walkpath(src_dir))
                        dest_files = collect(walkpath(dest_dir))

                        # Test destination directory has expected files
                        @test !isempty(dest_files)
                        @test length(dest_files) == length(src_files)

                        # Test directories are the same
                        compare_dir(src_dir, dest_dir)

                        # Test readdir only lists files and "dirs" within this S3 "dir"
                        @test readdir(dest_dir) == ["file1", "file2", "folder/"]
                        @test readdir(Path("$s3_prefix/")) == [
                            "folder1/", "folder2/", "presign/"
                        ]
                        # Not including the ending `/` means this refers to an object and
                        # not a directory prefix in S3
                        @test_throws ArgumentError readdir(Path(s3_prefix))

                        @testset "Sync modified dest file" begin
                            # Modify a file in dest
                            s3_put(
                                dest_files[1].bucket,
                                dest_files[1].key,
                                "Modified in dest.",
                            )

                            # Syncing overwrites the newer file in dest because it is of
                            # a different size
                            sync(src_dir, dest_dir)

                            # Test directories are the same
                            compare_dir(src_dir, dest_dir)

                            @test read(dest_files[1], String) == s3_objects[3]["Content"]
                        end

                        @testset "Sync modified src file" begin
                            # Modify a file in src
                            s3_objects[3]["Content"] = "Modified in src."
                            s3_put(
                                s3_objects[3]["Bucket"],
                                s3_objects[3]["Key"],
                                s3_objects[3]["Content"],
                            )

                            # Test that syncing overwrites the modified file in dest
                            sync(src_dir, dest_dir)

                            # Test directories are the same
                            compare_dir(src_dir, dest_dir)

                            @test read(dest_files[1], String) == s3_objects[3]["Content"]
                        end

                        @testset "Sync newer file in dest" begin
                            # Modify a file in dest
                            s3_put(
                                dest_files[1].bucket,
                                dest_files[1].key,
                                "Modified in dest",
                            )

                            # Test that syncing doesn't overwrite the newer file in dest
                            # This is the case because a newer file of the same size is
                            # usually the result of an uploaded file always having a newer
                            # last_modified time.
                            sync(src_dir, dest_dir)

                            file_contents = read(dest_files[1], String)
                            @test file_contents != s3_objects[3]["Content"]
                            @test file_contents ==  "Modified in dest"
                        end

                        @testset "Sync s3 bucket with object prefix" begin
                            obj = s3_objects[3]
                            file = "s3://" * join([obj["Bucket"], obj["Key"]], '/')

                            @test startswith(file, "s3://")
                            @test_throws ArgumentError sync(Path(file), dest_dir)
                        end

                        rm(src_files[1])

                        @testset "Sync deleted file with no delete flag" begin
                            sync(src_dir, dest_dir)

                            # We collect the walkpath result because we want it to complete
                            # before checking the length
                            src_files = collect(walkpath(src_dir))
                            dest_files = collect(walkpath(dest_dir))

                            @test length(dest_files) == length(src_files) + 1
                        end

                        @testset "Sync deleted files with delete flag" begin
                            # Test that syncing deletes the file in dest
                            sync(src_dir, dest_dir; delete=true)

                            # We collect the walkpath result because we want it to complete
                            # before checking the length
                            src_files = collect(walkpath(src_dir))
                            dest_files = collect(walkpath(dest_dir))
                            @test length(dest_files) == length(src_files)
                        end

                        @testset "Sync files" begin
                            src_file = S3Path("$s3_prefix/folder1/file")
                            dest_file = S3Path("$s3_prefix/folder2/file")

                            # Modify file in src dir
                            write(src_file, "Test modified file in source")

                            # Test syncing individual files instead of directories
                            sync(src_file, dest_file)

                            # Test directories are the same
                            compare_dir(src_dir, dest_dir)

                            # Test destination file was modifies
                            @test read(dest_file, String) == "Test modified file in source"
                        end

                        @testset "Sync non-existent directory" begin
                            rm(src_dir; recursive=true)

                            # Error because src folder doesn't exist
                            @test_throws ArgumentError sync(src_dir, dest_dir; delete=true)

                            src_files = collect(walkpath(src_dir))
                            @test isempty(src_files)

                            rm(dest_dir; recursive=true)
                            dest_files = collect(walkpath(dest_dir))
                            @test isempty(dest_files)
                        end
                    end

                finally
                    # Clean up any files left in the test directory
                    rm(Path("$s3_prefix/"); recursive=true)

                    # Delete bucket if it was explicitly created
                    if TEST_BUCKET_AND_PREFIX === nothing
                        s3_bucket_dir = replace(s3_prefix, r"^(s3://[^/]+).*$" => s"\1")
                        bucket, key = bucket_and_key(s3_bucket_dir)
                        @info "Deleting S3 bucket $bucket"
                        rm(Path("s3://$bucket/"); recursive=true)
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
end
