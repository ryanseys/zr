# frozen_string_literal: true

require "test_helper"
require "fileutils"
require "tmpdir"
require_relative "../../lib/zr/runtime"

# What the runtime's digest covers, and what it leaves out.
#
# The digest names the cached runtime object, the prelinked image and the
# eval road, so a file it leaves out is a file whose change goes
# unnoticed -- and a stale runtime object is a silently wrong binary. So
# everything under `lib` counts unless `Zr::LINK_ONLY` names it, and what
# it names is folded into the image the link writes instead. A second
# list, `Zr::PER_TARGET`, leaves a backend and an object writer out of
# every target but the one that emits with them.
class DigestTest < Minitest::Test
  LIB = File.join(ROOT, "lib/zr")

  def compiler = Dir[File.join(LIB, "**/*.rb")].sort

  def test_every_file_of_the_compiler_is_in_one_digest_or_the_other
    covered = Zr::Target.all.flat_map { |target| Zr.compiler_files(target) } + Zr::LINK_ONLY

    assert_equal compiler, covered.uniq.sort
  end

  def test_the_files_left_out_are_left_out_by_name
    Zr::LINK_ONLY.each { |path| assert_path_exists path }
    assert_empty Zr::LINK_ONLY & Zr.sources
  end

  # The default is to count: a file no prefix names is in every target's
  # digest, so a new file of the compiler is covered until someone takes
  # it out by name.
  def test_a_file_no_prefix_names_counts_for_every_target
    named = compiler.select do |path|
      Zr::PER_TARGET.keys.any? { |prefix| path.delete_prefix("#{LIB}/").start_with?(prefix) }
    end
    shared = Zr::Target.all.map { |target| Zr.compiler_files(target) }.reduce(:&)

    assert_equal (compiler - named - Zr::LINK_ONLY).sort, shared.sort
  end

  def test_a_backend_and_an_object_writer_belong_to_the_target_they_emit_for
    darwin = Zr.compiler_files(Zr::Target::AARCH64_DARWIN)
    wasm = Zr.compiler_files(Zr::Target::WASM32_WASI)

    assert_includes darwin, File.join(LIB, "backend/aarch64/codegen.rb")
    assert_includes darwin, File.join(LIB, "obj/macho/object_file.rb")
    refute_includes darwin, File.join(LIB, "backend/wasm/codegen.rb")
    refute_includes darwin, File.join(LIB, "obj/elf/object_file.rb")
    assert_includes wasm, File.join(LIB, "backend/wasm/codegen.rb")
    refute_includes wasm, File.join(LIB, "backend/aarch64/codegen.rb")
    refute_includes wasm, File.join(LIB, "obj/macho/object_file.rb")
  end

  # The runtime is lowered again when the lowering changes, and not when
  # a linker does. Both are asked of a copy of the compiler, since the
  # answer depends on the bytes on disk.
  def test_a_lowering_file_moves_the_runtime_digest_and_a_linker_does_not
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

  # A copy of the compiler to write into, with the runtime and the
  # vendored libraries beside it as links and a cache of its own. The
  # check never writes under `lib`: other workers of this run read those
  # files for their own digests, and one that read a file mid-write took
  # a runtime nobody had built and spent its deadline building it.
  def copied
    Dir.mktmpdir("zr-digest-") do |dir|
      root = File.realpath(dir)
      FileUtils.cp_r(File.join(ROOT, "lib"), File.join(root, "lib"))
      %w[runtime vendor].each { |name| File.symlink(File.join(ROOT, name), File.join(root, name)) }
      yield root
    end
  end

  # `[runtime digest, link digest]` of the compiler under `root`, asked
  # in a child so this process keeps neither answer.
  def digests(root)
    env = Zr::Harness::CleanEnv.env.merge("ZR_CACHE" => File.join(root, "cache"))
    said = IO.popen(env, [RbConfig.ruby, "-I#{root}/lib", "-e", <<~RUBY],
      require "zr/runtime"
      puts Zr::Runtime.new(Zr::Target.default).digest
      puts Zr.link_digest
    RUBY
                    unsetenv_others: true, &:read)
    assert_predicate $?, :success?, "the child did not answer: #{said}"
    said.lines(chomp: true)
  end

  # `path` with a comment added for the block, and put back after.
  def touching(path)
    was = File.binread(path)
    File.binwrite(path, "#{was}\n# a comment this check wrote\n")
    yield
  ensure
    File.binwrite(path, was)
  end
end
