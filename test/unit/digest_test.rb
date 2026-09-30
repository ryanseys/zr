# frozen_string_literal: true

require "test_helper"
require "fileutils"
require "tmpdir"
require_relative "../../lib/zr/runtime"

# Tests which files the runtime digest includes and which it leaves out.
#
# The digest identifies the cached runtime object, the prelinked image
# and eval support. A change to a file that it leaves out is not seen,
# and a stale runtime object gives a wrong binary with no error. Thus all
# of `lib` counts, except the files in `Zr::RuntimeSources::LINK_ONLY`, which go into the
# link digest, and the files in `Zr::RuntimeSources::DRIVER_ONLY`, which no build or link
# loads (`compiler_digest_test.rb`). `Zr::RuntimeSources::PER_TARGET` keeps a backend and an object writer only
# in the digest of the target that uses them.
class DigestTest < Minitest::Test
  LIB = File.join(ROOT, "lib/zr")

  def compiler = Dir[File.join(LIB, "**/*.rb")].sort

  def test_every_compiler_file_is_in_a_digest
    covered = Zr::Target.all.flat_map { |target| Zr::RuntimeSources.for(target).compiler_files } + Zr::RuntimeSources::LINK_ONLY + Zr::RuntimeSources::DRIVER_ONLY

    assert_equal compiler, covered.uniq.sort
  end

  def test_the_files_left_out_are_left_out_by_name
    (Zr::RuntimeSources::LINK_ONLY + Zr::RuntimeSources::DRIVER_ONLY).each { |path| assert_path_exists path }
    assert_empty (Zr::RuntimeSources::LINK_ONLY + Zr::RuntimeSources::DRIVER_ONLY) & Zr::RuntimeSources.for.sources
  end

  # By default a file counts. A file that no prefix matches is in the
  # digest of every target. Thus a new compiler file is included until
  # someone removes it explicitly.
  def test_file_without_target_prefix_is_in_every_target_digest
    named = compiler.select do |path|
      Zr::RuntimeSources::PER_TARGET.keys.any? { |prefix| path.delete_prefix("#{LIB}/").start_with?(prefix) }
    end
    shared = Zr::Target.all.map { |target| Zr::RuntimeSources.for(target).compiler_files }.reduce(:&)

    assert_equal (compiler - named - Zr::RuntimeSources::LINK_ONLY - Zr::RuntimeSources::DRIVER_ONLY).sort, shared.sort
  end

  def test_backend_files_are_only_in_their_target_digest
    darwin = Zr::RuntimeSources.for(Zr::Target::AARCH64_DARWIN).compiler_files
    wasm = Zr::RuntimeSources.for(Zr::Target::WASM32_WASI).compiler_files

    assert_includes darwin, File.join(LIB, "backend/aarch64/codegen.rb")
    assert_includes darwin, File.join(LIB, "obj/macho/object_file.rb")
    refute_includes darwin, File.join(LIB, "backend/wasm/codegen.rb")
    refute_includes darwin, File.join(LIB, "obj/elf/object_file.rb")
    assert_includes wasm, File.join(LIB, "backend/wasm/codegen.rb")
    refute_includes wasm, File.join(LIB, "backend/aarch64/codegen.rb")
    refute_includes wasm, File.join(LIB, "obj/macho/object_file.rb")
  end

  # The runtime is lowered again when a lowering file changes, but not
  # when a linker changes. The test uses a copy of the compiler, because
  # the digest depends on the bytes on disk.
  def test_runtime_digest_changes_for_lowering_and_not_for_linker
    copied do |root|
      was = digests(root)
      touching(File.join(root, "lib/zr/hir/build.rb")) do
        refute_equal was.first, digests(root).first, "the runtime digest ignored the front end"
      end
      touching(File.join(root, "lib/zr/obj/macho/prelink.rb")) do
        assert_equal was.first, digests(root).first, "the runtime digest followed the linker"
        refute_equal was.last, digests(root).last, "the link digest ignored the linker"
      end
      touching(File.join(root, "lib/zr/backend/wasm/codegen.rb")) do
        assert_equal was.first, digests(root).first, "the native runtime digest followed the wasm backend"
      end
    end
  end

  private

  # Yields a copy of the compiler that the test can write. The runtime
  # and vendored libraries are symlinks, and the copy has its own cache.
  # The test never writes under the real `lib`: other workers read those
  # files for their digests. A worker that read a half-written file got
  # an unbuilt runtime and used all its time to build it.
  def copied
    Dir.mktmpdir("zr-digest-") do |dir|
      root = File.realpath(dir)
      FileUtils.cp_r(File.join(ROOT, "lib"), File.join(root, "lib"))
      %w[runtime vendor].each { |name| File.symlink(File.join(ROOT, name), File.join(root, name)) }
      yield root
    end
  end

  # Returns `[runtime digest, link digest]` of the compiler under `root`.
  # A child process computes them, so that this process caches neither.
  def digests(root)
    env = Zr::Harness::CleanEnv.env.merge("ZR_CACHE" => File.join(root, "cache"))
    said = IO.popen(env, [RbConfig.ruby, "-I#{root}/lib", "-e", <<~RUBY],
      require "zr/runtime"
      puts Zr::Runtime.new(Zr::Target.default).digest
      puts Zr::Digests.link
    RUBY
                    unsetenv_others: true, &:read)
    assert_predicate $?, :success?, "the child did not answer: #{said}"
    said.lines(chomp: true)
  end

  # Adds a comment to `path` for the block, and restores the file after.
  def touching(path)
    was = File.binread(path)
    File.binwrite(path, "#{was}\n# a comment this check wrote\n")
    yield
  ensure
    File.binwrite(path, was)
  end
end
