# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require_relative "../../lib/zr/ext"
require_relative "../../lib/zr/ext/c_api"

# The readers that find a C extension to link: mkmf's Makefile
# (`Zr::Ext::Makefile`), an installed gem's extensions (`Ext::Source`),
# and the C API's names that an extension's imports are checked against
# (`Ext::CApi`).
class ExtTest < Minitest::Test
  MAKEFILE = <<~MAKE
    SHELL = /bin/sh
    srcdir = $(gem_srcdir)/ext/hello
    gem_srcdir = /src/hello-1.0
    target_prefix = /hello
    LOCAL_LIBS = -lfoo
    LIBS = $(LIBRUBYARG_SHARED) \\
    \t-lpthread -lm
    ORIG_SRCS = a.c b.c
    SRCS = $(ORIG_SRCS) extra.c
    OBJS = $(SRCS:.c=.o)
    TARGET = hello
    TARGET_NAME = hello_ext
    DLLIB = ${TARGET}.bundle
    LOOP = $(LOOP) x
    all:
    \t$(CC) -o $@ $(OBJS)
  MAKE

  def makefile = Zr::Ext::Makefile.new(MAKEFILE, dir: "/build/ext/hello")

  def test_a_variable_expands_its_references_as_make_does
    assert_equal "/src/hello-1.0/ext/hello", makefile["srcdir"]
    assert_equal "hello.bundle", makefile["DLLIB"]
    assert_equal "a.o b.o extra.o", makefile["OBJS"]
    assert_equal "x", makefile["LOOP"].strip, "a loop expands to nothing"
    assert_equal "", makefile["UNSET"]
  end

  def test_the_extension_has_its_feature_init_objects_and_libraries
    assert_equal "hello/hello", makefile.feature
    assert_equal "Init_hello_ext", makefile.init
    assert_equal %w[/build/ext/hello/a.o /build/ext/hello/b.o /build/ext/hello/extra.o], makefile.objects
    assert_equal %w[-lfoo -lpthread -lm], makefile.libraries
  end

  def test_a_top_level_extension_has_no_prefix
    top = Zr::Ext::Makefile.new("TARGET = bare\ntarget_prefix =\nOBJS = bare.o\n", dir: "/x")

    assert_equal "bare", top.feature
    assert_equal "Init_bare", top.init
  end

  # A gem's extension is where its objects are: a directory without them,
  # or without all of them, is not one.
  def test_an_installed_gem_gives_each_extension_whose_objects_are_there
    Dir.mktmpdir do |gem|
      ext = File.join(gem, "ext", "hello")
      FileUtils.mkdir_p(ext)
      File.write(File.join(ext, "Makefile"), MAKEFILE)
      %w[a.o b.o].each { |name| File.write(File.join(ext, name), "") }
      assert_empty Zr::Ext::Source.installed(gem)

      File.write(File.join(ext, "extra.o"), "")
      sources = Zr::Ext::Source.installed(gem)
      assert_equal 1, sources.size
      source = sources.first

      assert_equal File.join(gem, "lib", "hello", "hello.bundle"), source.bundle
      assert_equal "Init_hello_ext", source.init
      assert_equal %w[a.o b.o extra.o].map { |name| File.join(ext, name) }, source.objects
    end
  end

  # A precompiled gem ships a bundle for each ruby: the one for this ABI
  # is the extension that `require "x/x"` loads, through dlopen.
  def test_a_precompiled_gem_gives_its_bundle_for_this_abi
    Dir.mktmpdir do |gem|
      %w[3.4 4.0].each do |abi|
        FileUtils.mkdir_p(File.join(gem, "lib", "fancy", abi))
        File.write(File.join(gem, "lib", "fancy", abi, "fancy.bundle"), "")
      end
      source = Zr::Ext::Source.installed(gem).first

      assert_equal 1, Zr::Ext::Source.installed(gem).size
      assert_equal File.join(gem, "lib", "fancy", "fancy.bundle"), source.bundle
      assert_equal File.join(gem, "lib", "fancy", Zr::Ext::ABI, "fancy.bundle"), source.library
      assert_equal ["Init_fancy", [], [source.library]], [source.init, source.objects, source.binaries]
    end
  end

  # The Makefile that the host's install of a gem with a C extension left
  # gives the objects that the install compiled.
  def test_a_real_makefile_lists_the_objects_that_its_install_made
    # Bundler hides the gems outside the bundle, so the gem is found in
    # ruby's own gem directory.
    gem_dir = Dir[File.join(Gem.default_dir, "gems", "msgpack-*")].max
    skip "msgpack is not installed" unless gem_dir

    sources = Zr::Ext::Source.installed(gem_dir)

    assert_equal [File.join(gem_dir, "lib", "msgpack", "msgpack.bundle")], sources.map(&:bundle)
    assert_equal "Init_msgpack", sources.first.init
    assert_equal Dir[File.join(gem_dir, "ext", "msgpack", "*.o")].sort, sources.first.objects.sort
  end

  def test_the_c_api_has_its_functions_and_its_data
    names = Zr::Ext::CApi.names

    assert_includes names, "rb_define_method"
    assert_includes names, "rb_raise"
    assert_includes names, "rb_cObject"
    refute_includes names, "zr_capi_str", "a kernel helper is not C API"
    assert_equal %w[rb_not_a_function], Zr::Ext::CApi.missing(%w[rb_define_method memcpy rb_not_a_function rb_raise])
  end

  # A build of an extension that imports a function the C API lacks
  # stops with its name, before the link.
  def test_an_import_that_the_c_api_lacks_refuses_the_build
    skip "needs an aarch64-apple-darwin host" unless Zr::Target::AARCH64_DARWIN.native?

    Dir.mktmpdir do |dir|
      c = File.join(dir, "lacks.c")
      File.write(c, "void rb_not_a_function(void);\nvoid Init_lacks(void) { rb_not_a_function(); }\n")
      object = File.join(dir, "lacks.o")
      system("cc", "-c", c, "-o", object, exception: true)
      source = Zr::Ext::Source.given(File.join(dir, "lacks.bundle"), [object])

      error = assert_raises(Zr::Refused) { Zr::Ext::CApi.check!([source]) }
      assert_match(/\Alacks\.bundle: zr's C API has no rb_not_a_function yet/, error.message)

      # A bundle given alone is embedded: its own imports are checked.
      system("cc", "-bundle", "-undefined", "dynamic_lookup", c, "-o", source.bundle, exception: true)
      error = assert_raises(Zr::Refused) { Zr::Ext::CApi.check!([Zr::Ext::Source.given(source.bundle, [])]) }
      assert_match(/\Alacks\.bundle: zr's C API has no rb_not_a_function yet/, error.message)
    end
  end
end
