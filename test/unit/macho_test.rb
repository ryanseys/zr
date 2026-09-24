# frozen_string_literal: true

require "test_helper"
require_relative "../../lib/zr/obj/macho/object_file"
require_relative "../../lib/zr/native/link"

# Checks the Mach-O writer against `ld`: an object that Ruby writes must
# link and run.
class MachOTest < Minitest::Test
  # Only a darwin host has Mach-O, libSystem and the darwin JIT.
  def setup
    skip "needs an aarch64-apple-darwin host" unless Zr::Target::AARCH64_DARWIN.native?
  end

  Obj = Zr::Obj

  # `mov w0, #3; bl _exit`, the branch patched by the link.
  MAIN_EXIT_3 = [0x60, 0x00, 0x80, 0x52, 0x00, 0x00, 0x00, 0x94].pack("C*")

  def unit
    u = Obj::Unit.new
    u.function("main", MAIN_EXIT_3, relocs: [Obj::Reloc.new(4, :branch26, "exit")])
    u.datum("msg", :text_const, "hello, zr!\n", linkage: :export)
    u.datum("table", :data_const, "\0" * 8, relocs: [Obj::Reloc.new(0, :abs64, "msg")])
    u.datum("counter", :bss, 16)
    u
  end

  def test_the_symbol_table_reads_back
    Dir.mktmpdir("zr-macho-") do |dir|
      obj = File.join(dir, "u.o")
      File.binwrite(obj, Obj::MachO::ObjectFile.write(unit))
      names = IO.popen(["nm", obj], &:read).lines.map { |l| l.split.last(2).join(" ") }.sort
      assert_equal ["S _msg", "T _main", "U _exit", "b _counter", "s _table"], names
      relocs = IO.popen(["otool", "-r", obj], &:read)
      assert_includes relocs, "(__TEXT,__text) 1 entries"
      assert_includes relocs, "(__DATA,__const) 1 entries"
    end
  end

  def test_a_ruby_written_object_links_and_runs
    Dir.mktmpdir("zr-macho-") do |dir|
      obj = File.join(dir, "u.o")
      bin = File.join(dir, "u")
      File.binwrite(obj, Obj::MachO::ObjectFile.write(unit))
      assert_nil Zr::Native::Link.run([obj], bin)
      system(bin)
      assert_equal 3, $?.exitstatus
    end
  end

  # There are two ways to get the form that a link reads from a unit.
  # `of` builds it directly. `read(write(...))` writes a whole object file
  # to a string and parses the string. The long way costs 18% of a link.
  # The linker can use `of` only while the two results are exactly equal.
  def test_of_returns_what_write_then_read_returns
    long = Obj::MachO::ObjectFile.read(Obj::MachO::ObjectFile.write(unit))
    short = Obj::MachO::ObjectFile.of(unit)

    assert_equal long.symbols, short.symbols
    assert_equal long.strings, short.strings
    assert_equal long.sections.map(&:to_h), short.sections.map(&:to_h)
    assert_equal (0...long.count).map { |i| long.name(i) }, (0...short.count).map { |i| short.name(i) }
  end
end
