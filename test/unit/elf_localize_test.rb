# frozen_string_literal: true

require "test_helper"
require "open3"
require "tmpdir"
require_relative "../../lib/zr/obj/elf/localize"
require_relative "../../lib/zr/target"

# `Obj::Elf::Localize`: a static C extension's objects, joined by `cc -r`,
# keep only their Init function global, so two extensions that each
# define `buffer_new` link into one ELF binary. The names that zr's
# require reads (`zr_ext_*`) are there, and the extension's initializers
# run through them, not at the binary's start. Checked with the musl
# toolchain's readelf and a static link; the binary runs where this host
# can run it.
class ElfLocalizeTest < Minitest::Test
  Image = Zr::Obj::Elf::Image
  TARGET = Zr::Target::AARCH64_LINUX_MUSL

  # An extension `name`: a global that the other one defines too, a
  # constructor, a static helper, and an import.
  def extension(name) = <<~C
    #include <stdio.h>
    extern void rb_define_module(const char *);
    int counter;
    int buffer_new(void) { return #{name == "a" ? 1 : 2}; }
    __attribute__((constructor)) static void setup(void) { counter += 10; }
    void Init_#{name}(void) {
      rb_define_module("#{name.upcase}");
      printf("#{name}: buffer_new %d counter %d\\n", buffer_new(), counter);
    }
  C

  # Runs each extension as zr_ext_embedded does: its initializers, then
  # its Init function, all by the names that Localize gives.
  MAIN = <<~C
    #include <stdio.h>
    typedef void (*fn)(void);
    void rb_define_module(const char *name) { printf("module %s\\n", name); }
    #define EXT(init) extern fn zr_ext_inits_##init[], zr_ext_inits_end_##init[]; extern char zr_ext_offsets_##init[], zr_ext_offsets_end_##init[]; \\
      extern void zr_ext_##init(void);
    EXT(Init_a)
    EXT(Init_b)
    #define RUN(init) for (fn *at = zr_ext_inits_##init; at < zr_ext_inits_end_##init; at++) (*at)(); \\
      printf("offsets %d\\n", (int)(zr_ext_offsets_end_##init - zr_ext_offsets_##init)); zr_ext_##init();
    int main(void) { RUN(Init_a) RUN(Init_b) return 0; }
  C

  def setup
    @cc = TARGET.tool("cc") or skip "needs aarch64-linux-musl's cc"
    @readelf = TARGET.tool("readelf") or skip "needs aarch64-linux-musl's readelf"
    @dir = Dir.mktmpdir("elf-localize")
  end

  def teardown
    FileUtils.rm_rf(@dir) if @dir
  end

  def run!(*argv)
    out, status = Open3.capture2e(*argv, chdir: @dir)
    assert_predicate status, :success?, "#{argv.join(" ")}:\n#{out}"
    out
  end

  # The extension `name`, compiled from two objects, joined, localized.
  def localized(name)
    File.write(File.join(@dir, "#{name}.c"), extension(name))
    File.write(File.join(@dir, "#{name}_more.c"), "int #{name}_more(void) { return 3; }\n")
    run!(@cc, "-O2", "-fPIC", "-c", "#{name}.c", "-o", "#{name}.o")
    run!(@cc, "-O2", "-fPIC", "-c", "#{name}_more.c", "-o", "#{name}_more.o")
    run!(@cc, "-r", "-nostdlib", "#{name}.o", "#{name}_more.o", "-o", "#{name}_joined.o")
    path = File.join(@dir, "#{name}_local.o")
    File.binwrite(path, Zr::Obj::Elf::Localize.call(File.binread(File.join(@dir, "#{name}_joined.o")), "Init_#{name}"))
    path
  end

  def test_only_init_and_zrs_names_stay_global
    image = Image.read(File.binread(localized("a")))

    assert_equal %w[Init_a zr_ext_Init_a zr_ext_base_Init_a zr_ext_inits_Init_a zr_ext_inits_end_Init_a
                    zr_ext_offsets_Init_a zr_ext_offsets_end_Init_a], image.defined
    assert_equal %w[printf rb_define_module], image.undefined
    locals = image.symbols.select { |symbol| symbol.bind == Image::STB_LOCAL }.map(&:name)
    assert_includes locals, "buffer_new"
    assert_includes locals, "a_more"
    refute(image.sections.any? { |section| section.name.start_with?(".init_array") }, "the initializers moved")
  end

  def test_readelf_reads_the_rewritten_object_without_a_complaint
    path = localized("a")
    out, status = Open3.capture2e(@readelf, "-a", "-W", path)

    assert_predicate status, :success?, out
    refute_match(/warning|error|corrupt/i, out)
    assert_match(/\.zr_ext_inits/, out)
  end

  def test_two_extensions_with_one_global_name_link_into_one_binary
    File.write(File.join(@dir, "main.c"), MAIN)
    run!(@cc, "-c", "main.c", "-o", "main.o")
    binary = File.join(@dir, "both")
    run!(@cc, "-static", "-no-pie", "-o", binary, "main.o", localized("a"), localized("b"))
    skip "this host cannot run an aarch64-linux-musl binary" unless TARGET.runs_here?

    assert_equal "offsets 0\nmodule A\na: buffer_new 1 counter 10\noffsets 0\nmodule B\nb: buffer_new 2 counter 10\n", run!(binary)
  end
end
