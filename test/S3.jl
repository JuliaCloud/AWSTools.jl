using AWSCore
using AWSTools.S3
using FilePathsBase
using UUIDs

using AWSTools.CloudFormation: stack_output
using AWSTools.S3: list_files, sync_key
using AWSS3: s3_create_bucket, s3_put

setlevel!(getlogger(AWSTools.S3), "info")

# Enables the running of the "batch" online tests. e.g ONLINE=batch
const ONLINE = strip.(split(get(ENV, "ONLINE", ""), r"\s*,\s*"))

# Get the stackname that has the CI testing bucket name (used by gitlab ci)
const AWS_STACKNAME = get(ENV, "AWS_STACKNAME", "")

# Run the online S3 tests on the bucket specified
const TEST_BUCKET_DIR = let
    if haskey(ENV, "TEST_BUCKET_DIR")
        if startswith(ENV["TEST_BUCKET_DIR"], "s3://")
            ENV["TEST_BUCKET_DIR"]
        else
            error("`TEST_BUCKET_DIR` must include the S3 prefix \"s3://\"")
        end
    elseif !isempty(AWS_STACKNAME)
        output = stack_output(AWS_STACKNAME)
        bucket_dir = output["TestBucketDir"]
        "s3://$bucket_dir"
    else
        nothing
    end
end


function compare(src_file::AbstractPath, dest_file::AbstractPath)
    @test isfile(dest_file)
    @test basename(dest_file) == basename(src_file)
    @test size(dest_file) == size(src_file)
    @test modified(dest_file) >= modified(src_file)

    # Test file contents are equal
    @test read(dest_file, String) == read(src_file, String)
end

function compare_dir(src_dir::AbstractPath, dest_dir::AbstractPath)
    @test isdir(dest_dir)

    src_contents = sort!(list_files(src_dir))
    dest_contents = sort!(list_files(dest_dir))

    src_keys = map(x -> sync_key(src_dir, x), src_contents)
    dest_keys = map(x -> sync_key(dest_dir, x), dest_contents)
    @test src_keys == dest_keys

    for i in 1:length(src_contents)
        compare(src_contents[i], dest_contents[i])
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
    @testset "Download object" begin
        content = format_s3_objects([
            ("bucket", "test_file"),
        ])

        mktempdir() do tmp_dir
            apply(s3_patches!(content)) do
                # Download to local file
                s3_object = S3Path("bucket", "test_file")
                localfile = Path((tmp_dir, "local_file"))
                downloaded_file = download(s3_object, localfile::AbstractPath)
                @test readdir(tmp_dir) == ["local_file"]
                @test isa(downloaded_file, AbstractPath)

                # Download to directory
                s3_object = S3Path("bucket", "test_file")
                downloaded_file = download(s3_object, tmp_dir::AbstractString)
                @test readdir(tmp_dir) == ["local_file", "test_file"]
                @test isa(downloaded_file, AbstractPath)
            end
        end
    end

    @testset "S3Path creation" begin
        # Test basic
        bucket = "bucket"
        key = "key"

        path1 = S3Path("s3://$bucket/$key")
        path2 = S3Path("$bucket", "$key")
        path3 = S3Path(("s3://$bucket", "$key"))
        path4 = S3Path("$bucket/$key")
        path5 = S3Path("s3://$bucket", "$key")

        @test path1.bucket == "$bucket"
        @test path1.key == "$key"
        @test parts(path1) == ("s3://$bucket", "$key")

        @test path1 == path2 == path3 == path4 == path5

        @test !isdirpath(path1)

        # Test longer key
        bucket = "bucket"
        key = "folder/key"
        pieces = ("s3://$bucket", "folder", "key")

        path1 = S3Path("s3://$bucket/$key")
        @test path1.bucket == "$bucket"
        @test path1.key == "$key"
        @test parts(path1) == pieces

        path2 = S3Path("$bucket", "$key")
        @test path2.bucket == "$bucket"
        @test path2.key == "$key"
        @test parts(path2) == pieces

        path3 = S3Path(pieces)
        @test path3.bucket == "$bucket"
        @test path3.key == "$key"
        @test parts(path3) == pieces

        path4 = S3Path("$bucket/$key")
        @test path3.bucket == "$bucket"
        @test path3.key == "$key"
        @test parts(path3) == pieces

        @test path1 == path2 == path3 == path4

        @test !isdirpath(path1)

        # Test folder
        bucket = "bucket"
        key = "folder1/folder2/"
        pieces = ("s3://$bucket", "folder1", "folder2", "")

        path1 = S3Path("s3://$bucket/$key")
        @test path1.bucket == "$bucket"
        @test path1.key == "$key"
        @test parts(path1) == pieces

        path2 = S3Path("$bucket", "$key")
        @test path2.bucket == "$bucket"
        @test path2.key == "$key"
        @test parts(path2) == pieces

        path3 = S3Path(pieces)
        @test path3.bucket == "$bucket"
        @test path3.key == "$key"
        @test parts(path3) == pieces

        path4 = S3Path("$bucket/$key")
        @test path3.bucket == "$bucket"
        @test path3.key == "$key"
        @test parts(path3) == pieces

        @test path1 == path2 == path3 == path4

        @test isdirpath(path1)

        # Test joins with folder
        joined_path = join(path1, "myfile")
        @test joined_path == S3Path("s3://$bucket/$(key)myfile")
        @test parts(joined_path) == ("s3://$bucket", "folder1", "folder2", "myfile")

        # Test bucket
        bucket = "bucket"
        key = ""
        pieces = ("s3://$bucket", "")

        path1 = S3Path("s3://$bucket/$key")
        @test path1.bucket == "$bucket"
        @test path1.key == "$key"
        @test parts(path1) == pieces

        path2 = S3Path("$bucket", "$key")
        @test path2.bucket == "$bucket"
        @test path2.key == "$key"
        @test parts(path2) == pieces

        path3 = S3Path(pieces)
        @test path3.bucket == "$bucket"
        @test path3.key == "$key"
        @test parts(path3) == pieces

        path4 = S3Path("$bucket/$key")
        @test path3.bucket == "$bucket"
        @test path3.key == "$key"
        @test parts(path3) == pieces

        @test path1 == path2 == path3 == path4

        @test isdirpath(path1)

        # Test joins with bucket
        joined_path = join(path1, "myfile")
        @test joined_path == S3Path("s3://$bucket/$(key)myfile")
        @test parts(joined_path) == ("s3://$bucket", "myfile")

        joined_path = join(path1, "folder/")
        @test joined_path == S3Path("s3://$bucket/$(key)folder/")
        @test parts(joined_path) == ("s3://$bucket", "folder", "")

        joined_path = join(path1, "")
        @test joined_path == path1
        @test parts(joined_path) == pieces
    end

    @testset "presign" begin
        @testset "minimum period" begin
            @test_throws InexactError AWSTools.S3.presign(
                S3Path("s3://bucket/file"),
                Dates.Millisecond(999),
            )
        end
    end

    @testset "Syncing" begin
        @testset "Sync two local directories" begin
            # Create files to sync
            src = Path(mktempdir())
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
            dest = Path(mktempdir())
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
                @test read(dest_folder_file, String) != read(src_folder_file, String)
            end

            @testset "Sync incompatible types" begin
                @test_throws ArgumentError sync(src, dest_folder_file)
                @test_throws ArgumentError sync(src_folder_file, dest)
            end

            remove(src_file)

            @testset "Sync deleted file with no delete flag" begin
                # Syncing should not delete the file in the destination
                sync(src, dest)
                @test isfile(dest_file)
            end

            @testset "Sync deleted files with delete flag" begin
                # Test that syncing deletes the file in dest
                sync(src, dest; delete=true)
                @test !isfile(dest_file)

                remove(Path(src_folder2); recursive=true)

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
                remove(src; recursive=true)

                sync(src, dest, delete=true)

                @test isempty(readdir(src))
                @test !isfile(dest) && !isdir(dest)
            end

            @testset "Sync non existent directories" begin
                remove(src; recursive=true)
                isdir(dest) && remove(dest; recursive=true)

                # Test syncing creates non existent local directories
                sync(src, dest)

                @test isdir(src)
                @test isdir(dest)

                remove(src)
                remove(dest)
            end
        end

        @testset "Sync two s3 directories" begin
            # Verify we don't run into errors and that the expected parameters are
            # passed to aws calls (via the patches)
            @testset "Sync two buckets" begin
                content = format_s3_objects([
                    ("bucket-1", "file1"),
                    ("bucket-1", "file2"),
                    ("bucket-1", "folder1/file3"),
                ])
                changes = []
                expected_changes = [
                    :copy => Dict(
                        :from => ("bucket-1", "folder1/file3"),
                        :to   => ("bucket-2", "folder1/file3"),
                    )
                    :copy => Dict(
                        :from => ("bucket-1", "file1"),
                        :to   => ("bucket-2", "file1"),
                    )
                    :copy => Dict(
                        :from => ("bucket-1", "file2"),
                        :to   => ("bucket-2", "file2"),
                    )
                ]

                apply(s3_patches!(content, changes)) do
                    sync("s3://bucket-1/", "s3://bucket-2/")
                    @test changes == expected_changes
                    empty!(changes)

                    # No deletions
                    sync("s3://bucket-1/", "s3://bucket-2/", delete=true)
                    @test changes == expected_changes
                    empty!(changes)
                end
            end

            @testset "Sync prefix in bucket to another bucket" begin
                content = format_s3_objects([
                    ("bucket-1", "dir1/file"),
                    ("bucket-1", "dir1/folder1/file"),
                ])
                changes = []
                expected_changes = [
                    :copy => Dict(
                        :from => ("bucket-1", "dir1/folder1/file"),
                        :to   => ("bucket-2", "folder1/file"),
                    ),
                    :copy => Dict(
                        :from => ("bucket-1", "dir1/file"),
                        :to   => ("bucket-2", "file"),
                    ),
                ]

                apply(s3_patches!(content, changes)) do
                    sync("s3://bucket-1/dir1/", "s3://bucket-2/")
                    @test changes == expected_changes
                    empty!(changes)

                    # No deletions
                    sync("s3://bucket-1/dir1/", "s3://bucket-2/", delete=true)
                    @test changes == expected_changes
                    empty!(changes)
                end
            end

            @testset "Sync two prefixes in same bucket" begin
                content = format_s3_objects([
                    ("bucket-1", "dir1/folder1/file"),
                    ("bucket-1", "dir1/file"),
                    ("bucket-1", "dir2/folder2/file2"),
                ])
                changes = []
                expected_changes = [
                    :copy => Dict(
                        :from => ("bucket-1", "dir1/folder1/file"),
                        :to   => ("bucket-1", "dir2/folder1/file"),
                    ),
                    :copy => Dict(
                        :from => ("bucket-1", "dir1/file"),
                        :to   => ("bucket-1", "dir2/file"),
                    ),
                ]
                expected_delete = [
                    expected_changes...,
                    :delete => ("bucket-1", "dir2/folder2/file2"),
                ]

                apply(s3_patches!(content, changes)) do
                    sync("s3://bucket-1/dir1/", "s3://bucket-1/dir2/")
                    @test changes == expected_changes
                    empty!(changes)

                    sync("s3://bucket-1/dir1/", "s3://bucket-1/dir2/", delete=true)
                    @test changes == expected_delete
                    empty!(changes)
                end
            end

            @testset "Sync prefixes in different buckets" begin
                content = format_s3_objects([
                    ("bucket-1", "dir1/file"),
                    ("bucket-1", "dir1/folder1/file"),
                    ("bucket-2", "dir2/file2"),
                ])
                changes = []
                expected_changes = [
                    :copy => Dict(
                        :from => ("bucket-1", "dir1/folder1/file"),
                        :to   => ("bucket-2", "dir2/folder1/file"),
                    ),
                    :copy => Dict(
                        :from => ("bucket-1", "dir1/file"),
                        :to   => ("bucket-2", "dir2/file"),
                    ),
                ]
                expected_delete = [
                    expected_changes...,
                    :delete => ("bucket-2", "dir2/file2"),
                ]

                apply(s3_patches!(content, changes)) do
                    sync("s3://bucket-1/dir1/", "s3://bucket-2/dir2/")
                    @test changes == expected_changes
                    empty!(changes)

                    sync("s3://bucket-1/dir1/", "s3://bucket-2/dir2/", delete=true)
                    @test changes == expected_delete
                    empty!(changes)
                end
            end

            @testset "Sync bucket to prefix" begin
                content = format_s3_objects([
                    ("bucket-1", "folder1/file3") => Dict(),
                    ("bucket-1", "file1") => Dict(),
                    ("bucket-1", "file2") => Dict("Size" => "0"),
                    ("bucket-2", "dir2/folder2/file3") => Dict(),
                    ("bucket-2", "dir2/file2") => Dict("Size" => "12"),
                ])
                changes = []
                expected_changes = [
                    :copy => Dict(
                        :from => ("bucket-1", "folder1/file3"),
                        :to   => ("bucket-2", "dir2/folder1/file3"),
                    ),
                    :copy => Dict(
                        :from => ("bucket-1", "file1"),
                        :to   => ("bucket-2", "dir2/file1"),
                    ),
                    :copy => Dict(
                        :from => ("bucket-1", "file2"),
                        :to   => ("bucket-2", "dir2/file2"),
                    ),
                ]
                expected_delete = [
                    expected_changes...,
                    :delete => ("bucket-2", "dir2/folder2/file3"),
                ]

                apply(s3_patches!(content, changes)) do
                    sync("s3://bucket-1/", "s3://bucket-2/dir2/")
                    @test changes == expected_changes
                    empty!(changes)

                    sync("s3://bucket-1/", "s3://bucket-2/dir2/", delete=true)
                    @test changes == expected_delete
                    empty!(changes)
                end
            end
        end

        @testset "Sync local folder to s3 bucket" begin
            content = format_s3_objects([
                ("bucket-1", "folder1/file3"),
                ("bucket-1", "file1"),
                ("bucket-1", "file2"),
            ])
            changes = []
            expected_changes = [
                :put => Dict(
                    :dest => ("bucket-1", "folder/file"),
                    :data => "",
                ),
                :put => Dict(
                    :dest => ("bucket-1", "file"),
                    :data => "Hello World!",
                ),
            ]
            expected_delete = [
                expected_changes...,
                :delete => ("bucket-1", "folder1/file3"),
                :delete => ("bucket-1", "file1"),
                :delete => ("bucket-1", "file2"),
            ]

            mktempdir() do src
                apply(s3_patches!(content, changes)) do
                    src_file = "$src/file"
                    write(src_file, "Hello World!")

                    src_folder = "$src/folder"
                    mkdir(src_folder)
                    src_folder_file = "$src_folder/file"
                    touch(src_folder_file) # empty file

                    sync(src, "s3://bucket-1/")
                    @test changes == expected_changes
                    empty!(changes)

                    # S3 directory was not empty initially, so this will delete all
                    # its original files that are not also in src
                    sync(src, "s3://bucket-1/", delete=true)
                    @test changes == expected_delete
                    empty!(changes)
                end
            end
        end

        @testset "Sync s3 bucket to local folder" begin
            content = format_s3_objects([
                ("bucket-1", "folder1/file3") => Dict("Content" => "Test"),
                ("bucket-1", "file1") => Dict("Content" => "Hello World!"),
                ("bucket-1", "file2") => Dict("Content" => ""),
            ])

            mktempdir() do folder
                apply(s3_patches!(content)) do

                    src = Path("s3://bucket-1/")
                    dest = Path(folder)

                    sync(src, dest)

                    s3_objects = list_files(src)

                    # Test directories are the same
                    compare_dir(src, dest)

                    @testset "Sync modified dest file" begin
                        # Modify a file in dest
                        s3_object = s3_objects[1]
                        file = join(dest, sync_key(src, s3_object))
                        write(file, "Modified in dest.")

                        # Syncing overwrites the newer file in dest because it is of
                        # different size
                        sync(src, dest)
                        compare(s3_object, file)
                    end

                    @testset "Sync newer dest file" begin
                        # This is the case because a newer file of the same size is usually
                        # the result of an uploaded file always having a newer last_modified
                        # time.

                        # Modify a file in dest
                        s3_object = s3_objects[1]
                        file = join(dest, sync_key(src, s3_object))
                        write(file, "Hello World.")

                        # Test that syncing doesn't overwrite the newer file in dest
                        sync(src, dest)

                        # Test file contents are not equal
                        @test read(file, String) != read(s3_object)
                    end

                    @testset "Sync an object instead of a prefix" begin
                        s3_object_path = join(src, sync_key(src, s3_objects[1]))
                        @test_throws ArgumentError sync(s3_object_path, folder)
                    end
                end
            end
        end

        if "S3" in ONLINE
            @testset "Online" begin
                @info "Running ONLINE S3 tests"

                # Create bucket for tests
                s3_bucket_dir = if TEST_BUCKET_DIR === nothing
                    bucket = string("awstools-s3-test-temp-", uuid4())
                    @info "Creating S3 bucket $bucket"
                    s3_create_bucket(bucket)
                    "s3://$bucket"
                else
                    rstrip(TEST_BUCKET_DIR, '/')
                end

                test_run_id = string(uuid4())
                s3_test_prefix = "$s3_bucket_dir/awstools/$test_run_id"

                try
                    @testset "Upload to S3" begin
                        dest = Path("$s3_test_prefix/folder3/testfile")

                        try
                            mktemp() do src, stream
                                write(stream, "Local file src")
                                close(stream)

                                @test list_files(dest) == []
                                @test !isfile(dest)
                                @test !isdir(parent(dest))

                                uploaded_file = upload(Path(src), dest)
                                @test isa(uploaded_file, S3Path)

                                @test list_files(dest) == [dest]
                                @test isfile(dest)
                                @test isdir(parent(dest))
                                @test read(dest, String) == "Local file src"
                            end
                        finally
                            remove(dest; recursive=true)
                        end
                    end

                    @testset "Download from S3" begin
                        src = Path("$s3_test_prefix/folder4/testfile")

                        try
                            s3_put(src.bucket, src.key, "Remote content")

                            @testset "Download to a directory" begin
                                mktempdir() do dest_dir
                                    dest = Path(dest_dir)

                                    dest_file = download(src, dest)
                                    @test isa(dest_file, AbstractPath)

                                    @test list_files(dest) == [Path(dest_file)]
                                    @test read(dest_file, String) == "Remote content"
                                end
                            end

                            @testset "Download to a local file" begin
                                mktemp() do dest_file, stream
                                    dest = Path(dest_file)
                                    close(stream)

                                    dest_file = download(src, dest; overwrite=true)
                                    @test isa(dest_file, AbstractPath)

                                    @test dest_file == String(dest)
                                    @test read(dest, String) == "Remote content"
                                end
                            end

                        finally
                            remove(src; recursive=true)
                        end
                    end

                    @testset "Download via presign" begin
                        src = Path("$s3_test_prefix/presign/file")
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
                        bucket, key_prefix = bucket_and_key(s3_test_prefix)

                        src_dir = Path("$s3_test_prefix/folder1/")
                        dest_dir = Path("$s3_test_prefix/folder2/")

                        # Directories should be empty, but just in case
                        # delete any pre-existing objects in the s3 bucket directories
                        remove(src_dir; recursive=true)
                        remove(dest_dir; recursive=true)

                        # Note: using `lstrip` for when `key_prefix` is empty
                        s3_objects = [
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

                        src_files = list_files(src_dir)
                        dest_files = list_files(dest_dir)

                        # Test destination directory has expected files
                        @test !isempty(dest_files)
                        @test length(dest_files) == length(s3_objects)

                        # Test directories are the same
                        compare_dir(src_dir, dest_dir)

                        # Test readdir only lists files and "dirs" within this S3 "dir"
                        @test readdir(dest_dir) == ["file1", "file2", "folder/"]
                        @test readdir(Path("$s3_test_prefix/")) == [
                            "folder1/", "folder2/", "presign/"
                        ]
                        # Not including the ending `/` means this refers to an object and
                        # not a directory prefix in S3
                        @test_throws ArgumentError readdir(
                            Path(s3_test_prefix)
                        )

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

                            @test read(dest_files[1], String) == s3_objects[1]["Content"]
                        end

                        @testset "Sync modified src file" begin
                            # Modify a file in src
                            s3_objects[1]["Content"] = "Modified in src."
                            s3_put(
                                s3_objects[1]["Bucket"],
                                s3_objects[1]["Key"],
                                s3_objects[1]["Content"],
                            )

                            # Test that syncing overwrites the modified file in dest
                            sync(src_dir, dest_dir)

                            # Test directories are the same
                            compare_dir(src_dir, dest_dir)

                            @test read(dest_files[1], String) == s3_objects[1]["Content"]
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
                            @test file_contents != s3_objects[1]["Content"]
                            @test file_contents ==  "Modified in dest"
                        end

                        @testset "Sync s3 bucket with object prefix" begin
                            obj = s3_objects[1]
                            file = "s3://" * join([obj["Bucket"], obj["Key"]], '/')

                            @test startswith(file, "s3://")
                            @test_throws ArgumentError sync(file, dest_dir)
                        end

                        remove(src_files[1])

                        @testset "Sync deleted file with no delete flag" begin
                            sync(src_dir, dest_dir)

                            src_files = list_files(src_dir)
                            dest_files = list_files(dest_dir)

                            @test length(dest_files) == length(src_files) + 1
                        end

                        @testset "Sync deleted files with delete flag" begin
                            # Test that syncing deletes the file in dest
                            sync(src_dir, dest_dir; delete=true)

                            src_files = list_files(src_dir)
                            dest_files = list_files(dest_dir)
                            @test length(dest_files) == length(src_files)
                        end

                        @testset "Sync files" begin
                            src_file = S3Path("$s3_test_prefix/folder1/file")
                            dest_file = S3Path("$s3_test_prefix/folder2/file")

                            # Modify file in src dir
                            write(src_file, "Test modified file in source")

                            # Test syncing individual files instead of directories
                            sync(src_file, dest_file)

                            # Test directories are the same
                            compare_dir(src_dir, dest_dir)

                            # Test destination file was modifies
                            @test read(dest_file, String) == "Test modified file in source"
                        end

                        @testset "Sync empty directory" begin
                            remove(src_dir; recursive=true)

                            sync(src_dir, dest_dir; delete=true)

                            src_files = list_files(src_dir)
                            dest_files = list_files(dest_dir)

                            @test isempty(src_files)
                            @test isempty(dest_files)
                        end
                    end

                finally
                    # Clean up any files left in the test directory
                    remove(Path("$s3_test_prefix/"); recursive=true)

                    # Delete bucket if it was explicitly created
                    if TEST_BUCKET_DIR === nothing
                        bucket, key = bucket_and_key(s3_bucket_dir)
                        @info "Deleting S3 bucket $bucket"
                        remove(S3Path(bucket); recursive=true)
                    end
                end
            end
        else
            @warn (
                "Skipping AWSTools.S3 ONLINE tests. Set `ENV[\"ONLINE\"] = \"S3\"` to run.\n" *
                "Can also optionally specify a test bucket name " *
                "`ENV[\"TEST_BUCKET_DIR\"] = \"s3://bucket/dir/\"`.\n" *
                "If `TEST_BUCKET_DIR` is not specified, a temporary bucket will be " *
                "created, used, and then deleted."
            )
        end
    end
end


