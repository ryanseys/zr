# frozen_string_literal: true

require_relative "helper"
require_relative "../../lib/ze0/obj/macho"
require_relative "../../lib/ze0/native/cranelift"

# The Mach-O writer, held to what `ld` accepts: a Ruby-written object
# links, runs, and links beside an object Cranelift wrote.
class MachOTest < Minitest::Test
  Obj = Ze0::Obj
  ROAD = Ze0::Native::Cranelift.new(ROOT)

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
      File.binwrite(obj, Obj::MachO.write(unit))
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
      File.binwrite(obj, Obj::MachO.write(unit))
      assert_nil ROAD.link([obj], bin)
      system(bin)
      assert_equal 3, $?.exitstatus
    end
  end

  # The data in Ruby's object, the code in Cranelift's: the two link into
  # one binary, so a Ruby backend can take over one function at a time.
  def test_a_ruby_written_data_object_links_beside_cranelift_code
    skip "clif2obj is not built (bin/ze0 native build)" unless ROAD.available?

    Dir.mktmpdir("ze0-macho-") do |dir|
      data = File.join(dir, "data.o")
      u = Obj::Unit.new
      u.datum("msg", :text_const, "hello, ze0!\n", linkage: :export)
      File.binwrite(data, Obj::MachO.write(u))
      code = File.join(dir, "code.o")
      assert_nil ROAD.compile(File.join(ROOT, "test/native/hello.clif"), code)
      bin = File.join(dir, "hello")
      assert_nil ROAD.link([code, data], bin)
      assert_equal "hello, ze0!\n", IO.popen([bin], &:read)
    end
  end
end
