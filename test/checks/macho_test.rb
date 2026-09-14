# frozen_string_literal: true

require_relative "helper"
require_relative "../../lib/ze0/obj/macho/object_file"
require_relative "../../lib/ze0/native/link"

# The Mach-O writer, held to what `ld` accepts: a Ruby-written object
# links and runs.
class MachOTest < Minitest::Test
  # Mach-O, libSystem and the darwin JIT: only a darwin host has them.
  def setup
    skip "needs an aarch64-apple-darwin host" unless Ze0::Target::AARCH64_DARWIN.native?
  end

  Obj = Ze0::Obj

  # `mov w0, #3; bl _exit`, the branch patched by the link.
  MAIN_EXIT_3 = [0x60, 0x00, 0x80, 0x52, 0x00, 0x00, 0x00, 0x94].pack("C*")

  def unit
    u = Obj::Unit.new
    u.function("main", MAIN_EXIT_3, relocs: [Obj::Reloc.new(4, :branch26, "exit")])
    u.datum("msg", :text_const, "hello, ze0!\n", linkage: :export)
    u.datum("table", :data_const, "\0" * 8, relocs: [Obj::Reloc.new(0, :abs64, "msg")])
    u.datum("counter", :bss, 16)
    u
  end

  def test_the_symbol_table_reads_back
    Dir.mktmpdir("ze0-macho-") do |dir|
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
    Dir.mktmpdir("ze0-macho-") do |dir|
      obj = File.join(dir, "u.o")
      bin = File.join(dir, "u")
      File.binwrite(obj, Obj::MachO::ObjectFile.write(unit))
      assert_nil Ze0::Native::Link.run([obj], bin)
      system(bin)
      assert_equal 3, $?.exitstatus
    end
  end
end
