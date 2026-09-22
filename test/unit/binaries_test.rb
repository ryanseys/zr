# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "support/binaries"

# The spec tier's kept binaries: a binary kept sparse comes back byte
# for byte, holds only what is the program's own, and a kept file that
# cannot come back whole is a miss rather than a wrong binary.
class BinariesTest < Minitest::Test
  Binaries = Ze0::Spec::Binaries
  SOURCE = "S = Struct.new(:a, :b)\nputs S.new(1, 2).inspect\n"

  def setup
    skip "a native link on this host only" unless Ze0::Target.default.link
    @work = File.realpath(Dir.mktmpdir("ze0-binaries-"))
    File.write(File.join(@work, "p.rb"), SOURCE)
    @program = Dir.chdir(@work) { Ze0::Native::Build.lower(SOURCE, "p.rb") }
    @bin = File.join(@work, "p")
    why = Ze0::Native::Build.program(@program, @bin, work: @work)
    raise why if why
  end

  def teardown
    FileUtils.rm_rf(@work) if @work
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

  def test_the_kept_form_holds_the_programs_own_bytes_only
    kept = File.join(@work, "kept")
    Binaries.keep(kept, @bin, @program, @work)

    assert_operator File.size(kept), :<, 1 << 20, "a kept binary is under a megabyte"
    holes = Binaries.cuts(File.binread(@bin), Ze0::Native::Build.prelink(Binaries.objects_of(@program)))
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
    program = Dir.chdir(@work) { Ze0::Native::Build.lower(source, "q.rb") }
    bin = File.join(@work, "q")
    raise why if (why = Ze0::Native::Build.program(program, bin, work: @work))
    kept = File.join(@work, "kept")

    Binaries.keep(kept, bin, program, @work)

    assert_includes File.binread(bin), @work, "the required file's path is the directory's, today"
    refute File.exist?(kept)
  end

  def test_trim_drops_the_binaries_used_longest_ago
    dir = File.join(@work, "binaries")
    FileUtils.mkdir_p(dir)
    %w[old mid new].each_with_index do |name, age|
      path = File.join(dir, name)
      File.binwrite(path, "x" * 100)
      File.utime(Time.now - (3 - age) * 60, Time.now - (3 - age) * 60, path)
    end

    Binaries.trim(250, dir)

    assert_equal %w[mid new], Dir.children(dir).sort
  end
end
