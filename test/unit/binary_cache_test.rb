# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "support/binaries"

# Tests the binary cache of the spec tier. A cached binary is stored
# sparse: it contains only the program's own bytes. It must come back
# byte for byte. A damaged cache file is a miss, not a wrong binary.
class BinaryCacheTest < Minitest::Test
  Binaries = Zr::Spec::Binaries
  SOURCE = "S = Struct.new(:a, :b)\nputs S.new(1, 2).inspect\n"

  def setup
    skip "a native link on this host only" unless Zr::Target.default.link
    @work = File.realpath(Dir.mktmpdir("zr-binaries-"))
    File.write(File.join(@work, "p.rb"), SOURCE)
    @program = Dir.chdir(@work) { Zr::Native::Build.lower(SOURCE, "p.rb") }
    @bin = File.join(@work, "p")
    why = Zr::Native::Build.program(@program, @bin, work: @work)
    raise why if why
  end

  def teardown
    FileUtils.rm_rf(@work) if @work
  end

  def test_an_edit_to_a_library_port_is_a_miss
    root = File.join(@work, "root")
    FileUtils.mkdir_p(File.join(root, "runtime/ext"))
    File.write(File.join(root, "runtime/ext/stringio.rb"), "# one\n")
    before = Binaries.library_digest(root)
    File.write(File.join(root, "runtime/ext/stringio.rb"), "# two\n")
    refute_equal before, Binaries.library_digest(root)

    target = Zr::Target.default
    a = stub_method(Binaries, :libraries, "a") { Binaries.path(target, SOURCE, "p.rb", {}) }
    b = stub_method(Binaries, :libraries, "b") { Binaries.path(target, SOURCE, "p.rb", {}) }
    refute_equal a, b
  end

  def test_a_kept_binary_comes_back_byte_for_byte
    kept = File.join(@work, "kept")
    Binaries.keep(kept, @bin, @program, @work)
    back = File.join(@work, "back")

    assert Binaries.take(kept, back)
    assert_equal File.binread(@bin), File.binread(back)
    assert File.executable?(back)
    assert_equal `#{@bin}`, `#{back}`
  end

  def test_kept_binary_contains_only_program_bytes
    kept = File.join(@work, "kept")
    Binaries.keep(kept, @bin, @program, @work)

    assert_operator File.size(kept), :<, 1 << 20, "a kept binary is under a megabyte"
    holes = Binaries.cuts(File.binread(@bin), Zr::Native::Build.prelink(Binaries.objects_of(@program)))
    assert_equal %i[text data symbols strings], holes.map(&:last)
    assert_operator holes.sum { |_, size, _| size }, :>, File.size(@bin) - (1 << 20)
  end

  def test_a_torn_kept_file_is_a_miss
    kept = File.join(@work, "kept")
    Binaries.keep(kept, @bin, @program, @work)
    File.binwrite(kept, File.binread(kept)[0, File.size(kept) / 2])
    back = File.join(@work, "back")

    refute Binaries.take(kept, back)
    refute File.exist?(back)
  end

  def test_a_binary_that_spells_where_it_was_built_is_not_kept
    source = "require_relative \"lib/helper\"\nputs Helper.answer\n"
    FileUtils.mkdir_p(File.join(@work, "lib"))
    File.write(File.join(@work, "lib/helper.rb"), "module Helper\n  def self.answer = __FILE__\nend\n")
    File.write(File.join(@work, "q.rb"), source)
    program = Dir.chdir(@work) { Zr::Native::Build.lower(source, "q.rb") }
    bin = File.join(@work, "q")
    why = Zr::Native::Build.program(program, bin, work: @work)
    raise why if why
    kept = File.join(@work, "kept")

    Binaries.keep(kept, bin, program, @work)

    assert_includes File.binread(bin), @work, "the required file's path is the directory's, today"
    refute File.exist?(kept)
  end
end
