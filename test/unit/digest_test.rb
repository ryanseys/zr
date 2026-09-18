# frozen_string_literal: true

require "test_helper"
require_relative "../../lib/ze0/zr"

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
  LIB = File.join(ROOT, "lib/ze0")

  def compiler = Dir[File.join(LIB, "**/*.rb")].sort

  def test_every_file_of_the_compiler_is_in_one_digest_or_the_other
    covered = Ze0::Target.all.flat_map { |target| Ze0::Zr.compiler_files(target) } + Ze0::Zr::LINK_ONLY

    assert_equal compiler, covered.uniq.sort
  end

  def test_the_files_left_out_are_left_out_by_name
    Ze0::Zr::LINK_ONLY.each { |path| assert_path_exists path }
    assert_empty Ze0::Zr::LINK_ONLY & Ze0::Zr.sources
  end

  # The default is to count: a file no prefix names is in every target's
  # digest, so a new file of the compiler is covered until someone takes
  # it out by name.
  def test_a_file_no_prefix_names_counts_for_every_target
    named = compiler.select do |path|
      Ze0::Zr::PER_TARGET.keys.any? { |prefix| path.delete_prefix("#{LIB}/").start_with?(prefix) }
    end
    shared = Ze0::Target.all.map { |target| Ze0::Zr.compiler_files(target) }.reduce(:&)

    assert_equal (compiler - named - Ze0::Zr::LINK_ONLY).sort, shared.sort
  end

  def test_a_backend_and_an_object_writer_belong_to_the_target_they_emit_for
    darwin = Ze0::Zr.compiler_files(Ze0::Target::AARCH64_DARWIN)
    wasm = Ze0::Zr.compiler_files(Ze0::Target::WASM32_WASI)

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
    was = digests
    touching(File.join(LIB, "hir/build.rb")) do
      refute_equal was.first, digests.first, "the runtime digest ignored the front end"
    end
    touching(File.join(LIB, "obj/macho/prelink.rb")) do
      assert_equal was.first, digests.first, "the runtime digest followed the linker"
      refute_equal was.last, digests.last, "the link digest ignored the linker"
    end
    touching(File.join(LIB, "backend/wasm/codegen.rb")) do
      assert_equal was.first, digests.first, "the native runtime digest followed the wasm backend"
    end
  end

  private

  # `[runtime digest, link digest]`, asked in a child so this process
  # keeps neither answer.
  def digests
    said = IO.popen(Ze0::Harness::Unbundled.env, [RbConfig.ruby, "-I#{ROOT}/lib", "-e", <<~RUBY],
      require "ze0/zr"
      puts Ze0::Zr::Runtime.new(Ze0::Target.default).digest
      puts Ze0::Zr.link_digest
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
