# frozen_string_literal: true
# zr-test: on musl

require "test_helper"
require "tmpdir"
require_relative "../../lib/zr/obj/image"
require_relative "../../lib/zr/ext/c_api"
require_relative "../../lib/zr/target"

# Checks `Obj::Elf::Image`, zr's reader of aarch64 ELF objects, against
# the musl toolchain's `nm`, on objects that its `cc` compiles from C
# like a C extension's: the names they define and import, their C
# strings, and the imports of a C extension made of two objects.
class ElfImageTest < Minitest::Test
  Image = Zr::Obj::Elf::Image
  TARGET = Zr::Target::AARCH64_LINUX_MUSL

  # Defines Init_shapes, a global, a common and a weak symbol; calls ruby
  # and libc; holds C strings, among them a feature that it requires.
  SHAPES = <<~'C'
    typedef unsigned long VALUE;
    extern VALUE rb_define_module(const char *);
    extern void rb_require(const char *);
    extern VALUE helper_area(VALUE);
    extern int printf(const char *, ...);
    int shapes_count;
    int shapes_total = 3;
    __attribute__((noipa)) static int hidden(int x) { return x + 1; }
    __attribute__((weak)) int shapes_hook(void) { return hidden(1); }
    void Init_shapes(void) {
      rb_require("shapes/core");
      rb_define_module("Shapes");
      printf("%d\n", (int)helper_area(shapes_total));
    }
  C

  # Defines what SHAPES uses of its own, and uses one more ruby name.
  HELPER = <<~'C'
    typedef unsigned long VALUE;
    extern VALUE rb_int2inum(long);
    VALUE helper_area(VALUE x) { return rb_int2inum((long)x * 2); }
  C

  def setup
    @cc = TARGET.tool("cc") or skip "needs aarch64-linux-musl's cc"
    @nm = TARGET.tool("nm") or skip "needs aarch64-linux-musl's nm"
    @dir = Dir.mktmpdir("elf-image")
  end

  def teardown
    FileUtils.rm_rf(@dir) if @dir
  end

  # The object that `cc -c` makes of `source`.
  def compile(name, source)
    c = File.join(@dir, "#{name}.c")
    File.write(c, source)
    object = File.join(@dir, "#{name}.o")
    system(@cc, "-O2", "-fPIC", "-c", c, "-o", object, exception: true)
    object
  end

  def nm(*args, path) = IO.popen([@nm, *args, path], err: File::NULL, &:read).lines.map { |line| line.split.last }.sort

  def test_the_symbols_are_those_that_nm_lists
    [compile("shapes", SHAPES), compile("helper", HELPER)].each do |path|
      image = Image.read(File.binread(path))
      assert_equal nm("-u", path).uniq, image.undefined, "undefined symbols of #{path}"
      assert_equal nm("-g", "--defined-only", path), image.defined, "defined symbols of #{path}"
    end
  end

  def test_a_symbol_has_its_binding_and_section
    image = Image.read(File.binread(compile("shapes", SHAPES)))
    by_name = image.symbols.to_h { |symbol| [symbol.name, symbol] }

    assert_equal Image::STB_LOCAL, by_name.fetch("hidden").bind
    assert_equal Image::STB_WEAK, by_name.fetch("shapes_hook").bind
    assert_predicate by_name.fetch("rb_require"), :undefined?
    assert_equal ".text", image.sections.fetch(by_name.fetch("Init_shapes").shndx).name
  end

  def test_the_c_strings_are_those_of_the_merged_string_sections
    image = Image.read(File.binread(compile("shapes", SHAPES)))

    assert_includes image.c_strings, "shapes/core"
    assert_includes image.c_strings, "Shapes"
    assert_equal "rb_require", image.c_name("rb_require")
  end

  def test_an_object_that_cc_r_joins_reads_as_one
    joined = File.join(@dir, "joined.o")
    system(@cc, "-r", "-nostdlib", compile("shapes", SHAPES), compile("helper", HELPER), "-o", joined, exception: true)
    image = Image.read(File.binread(joined))

    assert_equal nm("-u", joined).uniq, image.undefined
    assert_includes image.defined, "helper_area"
    refute_includes image.undefined, "helper_area"
  end

  def test_the_imports_of_an_extension_are_the_ruby_names_that_no_object_of_it_defines
    paths = [compile("shapes", SHAPES), compile("helper", HELPER)]

    assert_equal %w[rb_define_module rb_int2inum rb_require], Zr::Ext::CApi.imports(*paths).sort
  end

  def test_a_file_that_is_no_aarch64_elf_is_refused
    assert_raises(ArgumentError) { Image.read("\x7FELF\x01\x01\x01".b + ("\0" * 60)) }
    assert_raises(ArgumentError) { Image.read("not elf at all") }
  end
end
