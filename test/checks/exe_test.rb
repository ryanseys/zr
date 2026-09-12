# frozen_string_literal: true

require_relative "helper"
require_relative "../../lib/ze0/machine/lower"
require_relative "../../lib/ze0/native/build"
require_relative "../../lib/ze0/obj/exe"
require_relative "../../lib/ze0/obj/stamps"
require_relative "../native/fixtures"

# The link, in Ruby. Every program whose imports are all libSystem's --
# the hand-written IR floor and the whole kernel dialect -- becomes a
# signed `MH_EXECUTE` that `Obj::Exe` wrote by itself, and it prints what
# the linked binary prints.
#
# `native_test.rb` and `zr_test.rb` run the same programs through `cc`,
# so a failure here is this writer's and a failure there is the
# backend's.
class ExeTest < Minitest::Test
  def written(unit, dir, name)
    out = File.join(dir, name)
    assert_nil Ze0::Obj::Exe.write(unit, out), "#{name} was refused"
    out
  end

  def ran(bin, *args)
    out = IO.popen([bin, *args], err: %i[child out], &:read)
    [$?.exitstatus, out]
  end

  Ze0::Native::Fixtures::NAMES.each do |name|
    define_method("test_native_#{name}") do
      functions, data = Ze0::Native::Fixtures.build(name)
      Dir.mktmpdir("ze0-exe-") do |dir|
        status, out = ran(written(Ze0::Native::Build.unit(functions, data), dir, name))
        assert_equal 0, status, "#{name} exited #{status}: #{out}"
        assert_equal File.binread(File.join(ROOT, "test/native/#{name}.stdout")), out
      end
    end
  end

  Dir[File.join(ROOT, "test/zr/*.rb")].sort.each do |rb|
    name = File.basename(rb, ".rb")
    define_method("test_zr_#{name}") do
      functions, data, raw = Ze0::Machine.compile(File.read(rb), rb)
      Dir.mktmpdir("ze0-exe-") do |dir|
        status, out = ran(written(Ze0::Native::Build.unit(functions, data, raw: raw), dir, name), name)
        assert_equal 0, status, "#{name} exited #{status}: #{out}"
        assert_equal File.binread(rb.sub(/\.rb\z/, ".stdout")), out
      end
    end
  end

  # Apple Silicon runs nothing unsigned, and a ze0 binary loads libSystem
  # and nothing else.
  def test_the_image_is_signed_and_alone
    functions, data = Ze0::Native::Fixtures.build("hello")
    Dir.mktmpdir("ze0-exe-") do |dir|
      bin = written(Ze0::Native::Build.unit(functions, data), dir, "hello")
      assert system("codesign", "-v", bin, out: File::NULL, err: File::NULL), "codesign refused the signature"
      libs = IO.popen(["otool", "-L", bin], &:read).scan(%r{^\t(\S+)}).flatten
      assert_equal ["/usr/lib/libSystem.B.dylib"], libs
    end
  end

  # `ld` accepts `-stack_size` and writes nothing, so every binary it
  # linked runs on the 8 MB default. This one says what it means.
  def test_the_main_stack_is_the_size_the_build_asks_for
    functions, data = Ze0::Native::Fixtures.build("hello")
    Dir.mktmpdir("ze0-exe-") do |dir|
      bin = written(Ze0::Native::Build.unit(functions, data), dir, "hello")
      main = IO.popen(["otool", "-l", bin], &:read)[/cmd LC_MAIN.*?stacksize (\d+)/m, 1]
      assert_equal Ze0::Native::Build::STACK, Integer(main)
    end
  end

  # `ld` gives every link a fresh UUID and the signature then hashes the
  # page it sits in, which is why `Obj::Stamps` has to blank two ranges
  # before two links can be compared. This writer derives the UUID from
  # the image, so the bytes are a function of the program and its name.
  def test_two_writes_give_the_same_bytes
    functions, data = Ze0::Native::Fixtures.build("loops")
    Dir.mktmpdir("ze0-exe-") do |dir|
      out = File.join(dir, "loops")
      first = (Ze0::Obj::Exe.write(Ze0::Native::Build.unit(functions, data), out) or File.binread(out))
      second = (Ze0::Obj::Exe.write(Ze0::Native::Build.unit(functions, data), out) or File.binread(out))
      assert_equal first, second
      assert_equal 2, Ze0::Obj::Stamps.of(first).size, "the stamps ld writes are still there to find"
    end
  end

  # A program that imports nothing has no stubs, no GOT and no
  # __DATA_CONST at all, and an image with a zero-length segment does not
  # load.
  def test_a_program_that_imports_nothing_runs
    f = Ze0::IR::Function.new("main", %w[i32 i64], "i32")
    f.ret(f.iconst("i32", 7))
    Dir.mktmpdir("ze0-exe-") do |dir|
      bin = written(Ze0::Native::Build.unit([f], []), dir, "bare")
      assert_equal [7, ""], ran(bin)
      segments = IO.popen(["otool", "-l", bin], &:read).scan(/^ +segname (\S+)/).flatten.uniq
      assert_equal %w[__PAGEZERO __TEXT __LINKEDIT], segments
    end
  end

  # A symbol libSystem does not define belongs to a vendored archive, and
  # reading an archive is a real linker. It says which symbol, so a
  # fallback to `cc` is never a mystery.
  def test_an_archive_symbol_is_refused_by_name
    f = Ze0::IR::Function.new("main", %w[i32 i64], "i32")
    f.call(f.callee("onig_new", %w[i64], nil, colocated: false), [f.iconst("i64", 0)])
    f.ret(f.iconst("i32", 0))
    Dir.mktmpdir("ze0-exe-") do |dir|
      why = Ze0::Obj::Exe.write(Ze0::Native::Build.unit([f], []), File.join(dir, "regexp"))
      assert_equal "onig_new is not libSystem's", why
      refute File.exist?(File.join(dir, "regexp")), "it wrote a file it had refused"
    end
  end

  # The same program, both roads, one answer.
  def test_both_linkers_agree
    Dir.mktmpdir("ze0-exe-") do |dir|
      %w[hello loops].each do |name|
        functions, data = Ze0::Native::Fixtures.build(name)
        mine = ran(written(Ze0::Native::Build.unit(functions, data), dir, "#{name}-ruby"))
        theirs = File.join(dir, "#{name}-cc")
        assert_nil Ze0::Native::Build.binary(functions, data, theirs, work: dir, road: "cc")
        assert_equal mine, ran(theirs), "#{name} answers differently through cc"
      end
    end
  end
end
