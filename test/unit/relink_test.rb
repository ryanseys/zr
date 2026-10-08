# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require_relative "../../lib/zr/obj/macho/relink"
require_relative "../../lib/zr/obj/macho/executable"

# `Obj::MachO::Relink` reads a C extension's bundle for zr's linker to embed:
# the bundle's segments at a new place, the fixups that its rebases and
# binds become, the names that the program reads, and a refusal of what an
# embed cannot hold. The bundles are built here from C, as mkmf links one
# (`-bundle -undefined dynamic_lookup`).
class RelinkTest < Minitest::Test
  TINY = <<~C
    #include <string.h>
    unsigned long rb_intern(const char *);
    static const char *table[] = { "zero", "one" };
    static volatile int constructed;
    __attribute__((constructor)) static void construct(void) { constructed = 1; }
    const char *helper_name(void) { return table[1]; }
    unsigned long Init_tiny(void) { return rb_intern(table[0]) + strlen(table[1]) + constructed; }
  C

  def setup
    skip "needs an aarch64-apple-darwin host" unless Zr::Target::AARCH64_DARWIN.native?
    @dir = Dir.mktmpdir
  end

  def teardown
    FileUtils.rm_rf(@dir) if @dir
  end

  # Builds `source` into a bundle with the `extra` linker words.
  def bundle(name, source, *extra)
    c = File.join(@dir, "#{name}.c")
    File.write(c, source)
    out = File.join(@dir, "#{name}.bundle")
    system("cc", "-bundle", "-undefined", "dynamic_lookup", c, "-o", out, *extra, exception: true)
    File.binread(out)
  end

  def relink(name, source, *extra) = Zr::Obj::MachO::Relink.new(bundle(name, source, *extra), init: "Init_#{name}")

  def test_the_bundle_moves_whole_and_its_binds_go_to_the_runtime_or_libsystem
    tiny = relink("tiny", TINY)
    tiny.place!(0x2_0000_0000)
    image = Zr::Obj::MachO::Image.read(bundle("tiny", TINY))
    parts = tiny.parts(0)

    assert_equal %w[__ZRX0 __ZRD0], parts.map(&:name).grep(/X0|D0/)
    assert_equal image.segments.reject { |s| s.name == "__LINKEDIT" }.map { |s| 0x2_0000_0000 + s.vmaddr }, parts.map(&:vm)

    fixups, imports = tiny.fixups(->(name) { name == "_rb_intern" ? 0x1_0000_4000 : nil })
    by_slot = fixups.to_h { |f| [f.address - 0x2_0000_0000, f] }
    # A lazy pointer has a rebase to the stub helper and a bind: the bind wins.
    bound = image.binds.map(&:address)
    image.rebases.reject { |r| bound.include?(r.address) }.each do |r|
      assert_equal [:rebase, 0x2_0000_0000 + r.target], [by_slot.fetch(r.address).kind, by_slot.fetch(r.address).target]
    end
    intern = image.binds.find { |b| b.name == "_rb_intern" }
    assert_equal [:rebase, 0x1_0000_4000], [by_slot.fetch(intern.address).kind, by_slot.fetch(intern.address).target]
    assert_equal({ "strlen" => Zr::Obj::MachO::Executable::LIBSYSTEM }, imports)
  end

  def test_the_program_reads_the_init_and_the_initializers
    tiny = relink("tiny", TINY)
    tiny.place!(0x2_0000_0000)
    image = Zr::Obj::MachO::Image.read(bundle("tiny", TINY))
    symbols = tiny.symbols
    # This linker writes initializers as offsets; an older one as pointers.
    offsets = image.sections.find { |s| s.name == "__init_offsets" }
    pointers = image.sections.find { |s| s.name == "__mod_init_func" }
    first, last, size = offsets ? ["offsets", "offsets_end", 4] : ["inits", "inits_end", 8]

    assert_equal 0x2_0000_0000 + image.exports.find { |e| e.name == "_Init_tiny" }.address, symbols.fetch("_zr_ext_Init_tiny")
    assert_equal size, symbols.fetch("_zr_ext_#{last}_Init_tiny") - symbols.fetch("_zr_ext_#{first}_Init_tiny")
    assert_equal 0x2_0000_0000 + (offsets || pointers).addr, symbols.fetch("_zr_ext_#{first}_Init_tiny")
    assert_equal 0x2_0000_0000, symbols.fetch("_zr_ext_base_Init_tiny")
  end

  # A bind that names the bundle's own export finds it there, as a flat
  # lookup does.
  def test_a_bind_to_the_bundles_own_name_stays_in_the_bundle
    source = <<~C
      int shared_value = 7;
      extern int shared_value;
      int *Init_own(void) { return &shared_value; }
    C
    own = relink("own", source)
    own.place!(0x3_0000_0000)
    fixups, imports = own.fixups(->(_) { nil })

    assert_empty imports
    assert(fixups.all? { |f| f.kind == :rebase })
  end

  # A bundle linked with a flat namespace binds each name by a flat
  # lookup: the executable keeps the lookup (nil, no dylib) and loads
  # every dylib that the bundle loads, so dyld finds the name where it did
  # for the bundle.
  def test_a_flat_lookup_stays_flat_and_the_bundles_dylibs_load
    flat = relink("flat", "#include <string.h>\nunsigned long Init_flat(const char *s) { return strlen(s); }\n", "-flat_namespace")
    flat.place!(0x4_0000_0000)
    fixups, imports = flat.fixups(->(_) { nil })

    assert_equal({ "strlen" => nil }, imports)
    assert_includes fixups.map(&:kind), :bind
    assert_equal [Zr::Obj::MachO::Executable::LIBSYSTEM], flat.dylibs
  end

  def test_what_an_embed_cannot_hold_is_refused_with_its_reason
    {
      "tls" => ["__thread int counter;\nint Init_tls(void) { return ++counter; }\n", [], /thread-local variables/],
      "throws" => ["void __cxa_throw(void *, void *, void (*)(void *));\nvoid Init_throws(void) { __cxa_throw(0, 0, 0); }\n", [],
                   /C\+\+ throws exceptions/]
    }.each do |name, (source, extra, reason)|
      error = assert_raises(Zr::Obj::MachO::Refused, name) { relink(name, source, *extra) }
      assert_match reason, error.message
    end
  end

  def test_a_dylib_that_is_not_the_systems_is_refused
    lib = File.join(@dir, "libfoo.dylib")
    c = File.join(@dir, "foo.c")
    File.write(c, "int foo(void) { return 1; }\n")
    system("cc", "-dynamiclib", c, "-o", lib, exception: true)

    error = assert_raises(Zr::Obj::MachO::Refused) { relink("uses", "int foo(void);\nint Init_uses(void) { return foo(); }\n", lib) }
    assert_match(/loads .*libfoo\.dylib, which is not a system dylib/, error.message)
  end
end
