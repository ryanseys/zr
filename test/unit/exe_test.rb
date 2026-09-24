# frozen_string_literal: true

require "test_helper"
require_relative "../../lib/zr/machine/lower"
require_relative "../../lib/zr/native/build"
require_relative "../../lib/zr/obj/macho/executable"
require_relative "../../lib/zr/obj/macho/stamps"
require_relative "../native/fixtures"

# The link, in Ruby. Every program whose imports are all libSystem's --
# the hand-written IR floor, the whole kernel dialect, and a Ruby program
# with the runtime's object -- becomes a signed `MH_EXECUTE` that
# `Obj::MachO::Executable` wrote by itself, and it prints what the linked
# binary prints. The checks that link through `cc` say so by name.
class ExeTest < Minitest::Test
  # Mach-O, libSystem and the darwin JIT: only a darwin host has them.
  def setup
    skip "needs an aarch64-apple-darwin host" unless Zr::Target::AARCH64_DARWIN.native?
  end

  def written(unit, dir, name)
    out = File.join(dir, name)
    assert_nil Zr::Obj::MachO::Executable.write(unit, out), "#{name} was refused"
    out
  end

  def ran(bin, *args)
    out = IO.popen([bin, *args], err: %i[child out], &:read)
    [$?.exitstatus, out]
  end

  Zr::Native::Fixtures::NAMES.each do |name|
    define_method("test_native_#{name}") do
      functions, data = Zr::Native::Fixtures.build(name)
      Dir.mktmpdir("zr-exe-") do |dir|
        status, out = ran(written(Zr::Native::Build.unit(functions, data), dir, name))
        assert_equal 0, status, "#{name} exited #{status}: #{out}"
        assert_equal File.binread(File.join(ROOT, "test/native/#{name}.out")), out
      end
    end
  end

  Dir[File.join(ROOT, "test/machine/*.rb")].sort.each do |rb|
    name = File.basename(rb, ".rb")
    define_method("test_zr_#{name}") do
      functions, data, raw = Zr::Machine.compile(File.read(rb), rb)
      Dir.mktmpdir("zr-exe-") do |dir|
        status, out = ran(written(Zr::Native::Build.unit(functions, data, raw: raw), dir, name), name)
        assert_equal 0, status, "#{name} exited #{status}: #{out}"
        assert_equal File.binread(rb.sub(/\.rb\z/, ".out")), out
      end
    end
  end

  # Apple Silicon runs nothing unsigned, and a zr binary loads libSystem
  # and nothing else.
  def test_the_image_is_signed_and_alone
    functions, data = Zr::Native::Fixtures.build("hello")
    Dir.mktmpdir("zr-exe-") do |dir|
      bin = written(Zr::Native::Build.unit(functions, data), dir, "hello")
      assert system("codesign", "-v", bin, out: File::NULL, err: File::NULL), "codesign refused the signature"
      libs = IO.popen(["otool", "-L", bin], &:read).scan(%r{^\t(\S+)}).flatten
      assert_equal ["/usr/lib/libSystem.B.dylib"], libs
    end
  end

  # Nothing writes `LC_MAIN.stacksize` for an image no linker touched,
  # and a program left on the 8 MB default recurses an eighth as deep.
  # `ld` writes it from `-stack_size`; this writes the same number.
  def test_the_main_stack_is_the_size_the_build_asks_for
    functions, data = Zr::Native::Fixtures.build("hello")
    Dir.mktmpdir("zr-exe-") do |dir|
      bin = written(Zr::Native::Build.unit(functions, data), dir, "hello")
      assert_equal Zr::Native::Link::STACK, stacksize(bin)
      through_cc = File.join(dir, "hello-cc")
      assert_nil Zr::Native::Build.binary(functions, data, through_cc, work: dir, linker: "cc")
      assert_equal stacksize(bin), stacksize(through_cc), "the two linkers give different stack sizes"
    end
  end

  def stacksize(bin)
    Integer(IO.popen(["otool", "-l", bin], &:read)[/cmd LC_MAIN.*?stacksize (\d+)/m, 1])
  end

  # `ld` gives every link a fresh UUID and the signature then hashes the
  # page it sits in, which is why `Obj::MachO::Stamps` has to blank two ranges
  # before two links can be compared. This writer derives the UUID from
  # the image, so the bytes are a function of the program and its name.
  def test_two_writes_give_the_same_bytes
    functions, data = Zr::Native::Fixtures.build("loops")
    Dir.mktmpdir("zr-exe-") do |dir|
      out = File.join(dir, "loops")
      first = (Zr::Obj::MachO::Executable.write(Zr::Native::Build.unit(functions, data), out) or File.binread(out))
      second = (Zr::Obj::MachO::Executable.write(Zr::Native::Build.unit(functions, data), out) or File.binread(out))
      assert_equal first, second
      assert_equal 2, Zr::Obj::MachO::Stamps.of(first).size, "the stamps ld writes are still there to find"
    end
  end

  # The image says what it holds: `nm` reads the symbol table, and the
  # exports trie holds the one symbol an executable exports and nothing
  # else, which is what `-no_exported_symbols` leaves behind.
  def test_the_image_names_what_it_holds
    functions, data = Zr::Native::Fixtures.build("hello")
    Dir.mktmpdir("zr-exe-") do |dir|
      bin = written(Zr::Native::Build.unit(functions, data), dir, "hello")
      assert_equal %w[_main _msg], IO.popen(["nm", bin], &:read).scan(/^\S+ \S (\S+)$/).flatten.sort
      exports = IO.popen(["dyld_info", "-exports", bin], err: %i[child out], &:read)
      assert_equal ["__mh_execute_header"], exports.scan(/^\s+0x\h+\s+(\S+)$/).flatten
    end
  end

  # A program that imports nothing has no stubs, no GOT and no
  # __DATA_CONST at all, and an image with a zero-length segment does not
  # load.
  def test_a_program_that_imports_nothing_runs
    f = Zr::IR::Function.new("main", %w[i32 i64], "i32")
    f.ret(f.iconst("i32", 7))
    Dir.mktmpdir("zr-exe-") do |dir|
      bin = written(Zr::Native::Build.unit([f], []), dir, "bare")
      assert_equal [7, ""], ran(bin)
      segments = IO.popen(["otool", "-l", bin], &:read).scan(/^ +segname (\S+)/).flatten.uniq
      assert_equal %w[__PAGEZERO __TEXT __LINKEDIT], segments
    end
  end

  # A symbol this unit defines, reached through the GOT as an import
  # would be: the slot holds the symbol's address, so the load answers
  # the address and not the symbol's first eight bytes.
  def test_a_defined_symbol_reached_through_the_got_answers_its_address
    f = Zr::IR::Function.new("main", %w[i32 i64], "i32")
    write = f.callee("write", %w[i32 i64 i64], "i64", colocated: false)
    f.call_val(write, [f.iconst("i32", 1), f.symbol_value(f.symbol("msg", colocated: false)), f.iconst("i64", 8)])
    f.ret(f.iconst("i32", 0))
    data = [Zr::Obj::Data.new("msg", :text_const, "got slot\n", align: 8)]
    Dir.mktmpdir("zr-exe-") do |dir|
      assert_equal [0, "got slot"], ran(written(Zr::Native::Build.unit([f], data), dir, "got"))
    end
  end

  # A symbol libSystem does not define is another object's, and reading
  # objects is a real linker. It says which symbol, so a fallback to
  # `cc` is never a mystery.
  def test_a_symbol_libsystem_does_not_define_is_refused_by_name
    f = Zr::IR::Function.new("main", %w[i32 i64], "i32")
    f.call(f.callee("zr_elsewhere", %w[i64], nil, colocated: false), [f.iconst("i64", 0)])
    f.ret(f.iconst("i32", 0))
    Dir.mktmpdir("zr-exe-") do |dir|
      why = Zr::Obj::MachO::Executable.write(Zr::Native::Build.unit([f], []), File.join(dir, "parse"))
      assert_equal "zr_elsewhere is not libSystem's", why
      refute File.exist?(File.join(dir, "parse")), "it wrote a file it had refused"
    end
  end

  # The object the next checks link beside a unit of their own: a
  # function that writes what it is given, and a message.
  def other_object(name = "shout")
    f = Zr::IR::Function.new(name, %w[i64 i64], "i64")
    write = f.callee("write", %w[i32 i64 i64], "i64", colocated: false)
    f.ret(f.call_val(write, [f.iconst("i32", 1), f.args[0], f.args[1]]))
    data = [Zr::Obj::Data.new("b_msg", :text_const, "unused from b\n", align: 8)]
    Zr::Obj::MachO::ObjectFile.write(Zr::Native::Build.unit([f], data, export: true))
  end

  # A unit that reaches into `other_object` three ways: a call, an
  # address loaded through the GOT, and a pointer in its own data whose
  # addend skips into the message.
  def reaching_unit
    f = Zr::IR::Function.new("main", %w[i32 i64], "i32")
    shout = f.callee("shout", %w[i64 i64], "i64", colocated: false)
    pointer = f.fetch("i64", f.symbol_value(f.symbol("a_ptr")))
    f.call(shout, [pointer, f.iconst("i64", 7)])
    f.call(shout, [f.symbol_value(f.symbol("b_msg", colocated: false)), f.iconst("i64", 7)])
    f.ret(f.iconst("i32", 0))
    data = [Zr::Obj::Data.new("a_ptr", :data, "\0".b * 8, relocs: [Zr::Obj::Reloc.new(0, :abs64, "b_msg", 7)], align: 8)]
    Zr::Native::Build.unit([f], data)
  end

  def test_a_unit_links_with_another_object
    Dir.mktmpdir("zr-exe-") do |dir|
      bin = File.join(dir, "two")
      assert_nil Zr::Obj::MachO::Executable.write(reaching_unit, bin, objects: [other_object])
      assert_equal [0, "from b\nunused "], ran(bin)
    end
  end

  # A program's JIT finds symbols by a binary search of the image's own
  # symbol table, so the table holds every global sorted by name, and the
  # exports trie holds the header alone whatever the program does.
  def test_the_symbol_table_holds_every_global_sorted_by_name
    Dir.mktmpdir("zr-exe-") do |dir|
      bin = File.join(dir, "sorted")
      assert_nil Zr::Obj::MachO::Executable.write(reaching_unit, bin, objects: [other_object])
      names = IO.popen(["nm", "-p", bin], err: %i[child out], &:read).lines.map { |l| l.split.last }
      assert_includes names, "_shout"
      assert_includes names, "_b_msg"
      assert_equal names.sort, names, "the symbol table is in the order of its names"
      exports = IO.popen(["dyld_info", "-exports", bin], err: %i[child out], &:read).scan(/^\s+0x\h+\s+(\S+)$/).flatten
      assert_equal ["__mh_execute_header"], exports
      assert_equal [0, "from b\nunused "], ran(bin)
    end
  end

  def test_a_global_defined_twice_is_refused_by_name
    Dir.mktmpdir("zr-exe-") do |dir|
      bin = File.join(dir, "twice")
      why = Zr::Obj::MachO::Executable.write(reaching_unit, bin, objects: [other_object, other_object])
      assert_equal "b_msg is defined twice", why
      refute File.exist?(bin), "it wrote a file it had refused"
    end
  end

  # The other object reaches back into the unit: a call to a function
  # the unit defines, and a pointer to its data. A base's external slots
  # are the ones the image writes again for each program.
  def calling_object
    f = Zr::IR::Function.new("shout", %w[i64 i64], "i64")
    f.ret(f.call_val(f.callee("hook", %w[i64 i64], "i64", colocated: false), [f.args[0], f.args[1]]))
    table = Zr::Obj::Data.new("b_table", :data, "\0".b * 8, relocs: [Zr::Obj::Reloc.new(0, :abs64, "a_msg")], align: 8, linkage: :export)
    data = [Zr::Obj::Data.new("b_msg", :text_const, "unused from b\n", align: 8), table]
    Zr::Obj::MachO::ObjectFile.write(Zr::Native::Build.unit([f], data, export: true))
  end

  def hooked_unit
    hook = Zr::IR::Function.new("hook", %w[i64 i64], "i64")
    write = hook.callee("write", %w[i32 i64 i64], "i64", colocated: false)
    hook.ret(hook.call_val(write, [hook.iconst("i32", 1), hook.args[0], hook.args[1]]))
    f = Zr::IR::Function.new("main", %w[i32 i64], "i32")
    shout = f.callee("shout", %w[i64 i64], "i64", colocated: false)
    f.call(shout, [f.fetch("i64", f.symbol_value(f.symbol("b_table", colocated: false))), f.iconst("i64", 6)])
    f.ret(f.iconst("i32", 0))
    data = [Zr::Obj::Data.new("a_msg", :text_const, "hooks\n", align: 8, linkage: :export)]
    Zr::Native::Build.unit([f, hook], data)
  end

  def test_a_base_reaches_back_into_the_program
    Dir.mktmpdir("zr-exe-") do |dir|
      bin = File.join(dir, "hooked")
      assert_nil Zr::Obj::MachO::Executable.write(hooked_unit, bin, objects: [calling_object])
      assert_equal [0, "hooks\n"], ran(bin)
      segments = IO.popen(["otool", "-l", bin], &:read).scan(/^ +segname (\S+)/).flatten.uniq
      assert_equal %w[__PAGEZERO __TEXT __PROGRAM __DATA_CONST __DATA __DATA_PROGRAM __LINKEDIT], segments
      assert system("codesign", "-v", bin, out: File::NULL, err: File::NULL), "codesign refused the signature"
    end
  end

  # A base read back from its bytes links the same image as the base
  # linked just now.
  def test_a_kept_base_links_the_same_bytes
    base = Zr::Obj::MachO::Prelink.build([calling_object])
    kept = Zr::Obj::MachO::Prelink.load(base.dump)
    refute_nil kept
    assert_nil Zr::Obj::MachO::Prelink.load(base.dump[0...-1]), "a base cut short is a miss"
    Dir.mktmpdir("zr-exe-") do |dir|
      bins = [base, kept].map.with_index do |prelink, n|
        File.join(dir, "hooked").tap { |bin| assert_nil Zr::Obj::MachO::Executable.write(hooked_unit, bin, prelink: prelink) }
            .then { |bin| File.binread(bin).tap { File.rename(bin, "#{bin}#{n}") } }
      end
      assert_equal bins[0], bins[1]
    end
  end

  # A binary cloned from the base's skeleton, or written over the last
  # binary at its path, holds the bytes a binary written whole holds:
  # the skeleton is the header page and the text, the last binary holds
  # the same text, and the link writes the header and everything after
  # the text.
  def test_a_binary_cloned_or_written_over_is_the_binary_written_whole
    base = Zr::Obj::MachO::Prelink.build([calling_object])
    Dir.mktmpdir("zr-exe-") do |dir|
      skeleton = File.join(dir, "skeleton")
      File.binwrite(skeleton, Zr::Obj::MachO::Skeleton.bytes(base))
      # One name in every directory: the signature carries the name.
      whole, cloned = %w[whole cloned].zip([nil, skeleton]).map do |name, skeleton|
        bin = File.join(dir, name, "hooked")
        Dir.mkdir(File.dirname(bin))
        assert_nil Zr::Obj::MachO::Executable.write(hooked_unit, bin, prelink: base, skeleton: skeleton)
        File.binread(bin)
      end
      assert_equal whole, cloned

      # Over the last binary: a longer one first, so the end is cut.
      over = File.join(dir, "hooked")
      File.binwrite(over, whole + ("\xAA".b * 1000))
      assert_nil Zr::Obj::MachO::Executable.write(hooked_unit, over, prelink: base, skeleton: nil)
      assert_equal whole, File.binread(over)
      # A file whose text is not the base's is nobody's to write over.
      torn = whole.dup
      torn.setbyte(Zr::Obj::MachO::Prelink::PAGE + 100, torn.getbyte(Zr::Obj::MachO::Prelink::PAGE + 100) ^ 1)
      File.binwrite(over, torn)
      assert_nil Zr::Obj::MachO::Executable.write(hooked_unit, over, prelink: base, skeleton: skeleton)
      assert_equal whole, File.binread(over)

      # A skeleton of another size is somebody else's: the link writes whole.
      File.binwrite(skeleton, "not a skeleton")
      bin = File.join(dir, "hooked")
      assert_nil Zr::Obj::MachO::Executable.write(hooked_unit, bin, prelink: base, skeleton: skeleton)
      assert_equal whole, File.binread(bin)
      assert_equal [0, "hooks\n"], ran(bin)
    end
  end

  # The same program, both roads, one answer.
  def test_both_linkers_agree
    Dir.mktmpdir("zr-exe-") do |dir|
      %w[hello loops].each do |name|
        functions, data = Zr::Native::Fixtures.build(name)
        mine = ran(written(Zr::Native::Build.unit(functions, data), dir, "#{name}-ruby"))
        theirs = File.join(dir, "#{name}-cc")
        assert_nil Zr::Native::Build.binary(functions, data, theirs, work: dir, linker: "cc")
        assert_equal mine, ran(theirs), "#{name} answers differently through cc"
      end
    end
  end
end
