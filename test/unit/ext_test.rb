# frozen_string_literal: true
# zr-test: on macho

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

  # A rule gives a variable to the shell, which takes its quotes, as
  # raindrops's `-DRB_..=\"x\"` reaches cc.
  def test_a_variables_words_are_the_shells
    quoted = Zr::Ext::Makefile.new(%(CPPFLAGS = -DNAME=\\"x\\" -DTWO='a b' -I. $(DEFS)\nDEFS = -DZ\n), dir: "/build")

    assert_equal ["-DNAME=\"x\"", "-DTWO=a b", "-I.", "-DZ"], quoted.words("CPPFLAGS")
  end

  def test_the_extension_has_its_feature_init_objects_and_libraries
    assert_equal "hello/hello", makefile.feature
    assert_equal "Init_hello_ext", makefile.init
    assert_equal %w[/build/ext/hello/a.o /build/ext/hello/b.o /build/ext/hello/extra.o], makefile.objects
    assert_equal %w[-lfoo -lpthread -lm], makefile.libraries
  end

  def test_each_source_compiles_to_its_object_in_the_build_directory
    assert_equal [%w[/src/hello-1.0/ext/hello/a.c /build/ext/hello/a.o], %w[/src/hello-1.0/ext/hello/b.c /build/ext/hello/b.o],
                  %w[/src/hello-1.0/ext/hello/extra.c /build/ext/hello/extra.o]], makefile.sources
    sub = Zr::Ext::Makefile.new("srcdir = .\nSRCS = x.cpp sub/y.c\n", dir: "/b")
    assert_equal [%w[/b/x.cpp /b/x.o], %w[/b/sub/y.c /b/sub/y.o]], sub.sources
  end

  # A library path or an archive in the build directory becomes absolute:
  # the link of the bundle runs in another directory.
  def test_the_libraries_take_mkmfs_library_path_and_absolute_archives
    text = "LIBPATH = -L. -L/usr/lib -Lvendor/lib\nLOCAL_LIBS = vendor/libxml2.a /opt/libz.a\nLIBS = -lm -Wl,-x\n"
    assert_equal %w[-L/b -L/usr/lib -L/b/vendor/lib /b/vendor/libxml2.a /opt/libz.a -lm -Wl,-x],
                 Zr::Ext::Makefile.new(text, dir: "/b").libraries
  end

  # An extconf that adds its own archive to $LDFLAGS (hiredis's
  # libhiredis.a) has it in DLDFLAGS, after LIBPATH as mkmf's rule links
  # it. Only the libraries of DLDFLAGS come: its other words are options
  # for a bundle's link.
  def test_the_libraries_take_the_archives_of_dldflags
    text = "ldflags = -L. -rdynamic -Wl,-z,relro ./../../vendor/hiredis/libhiredis.a -lextra\n" \
           "dldflags = -undefined dynamic_lookup -multiply_defined suppress\nDLDFLAGS = $(ldflags) $(dldflags)\n" \
           "LIBPATH = -L/usr/lib\nLIBS = -lm\n"
    assert_equal %w[-L/usr/lib -L/b/ext/hiredis_ext /b/vendor/hiredis/libhiredis.a -lextra -lm],
                 Zr::Ext::Makefile.new(text, dir: "/b/ext/hiredis_ext").libraries
  end

  # mkmf on Linux links an extension with libruby (LIBRUBYARG_SHARED in
  # LIBS, or the static one); a zr binary is the ruby and links neither.
  def test_the_libraries_leave_out_rubys_own_library
    text = "RUBY_SO_NAME = ruby\nlibdir = /usr/local/lib\nLIBRUBYARG_SHARED = -Wl,-rpath,$(libdir) -L$(libdir) -l$(RUBY_SO_NAME)\n" \
           "LIBRUBYARG_STATIC = -l$(RUBY_SO_NAME)-static\nLIBPATH = -L. -L$(libdir)\n" \
           "LIBS = $(LIBRUBYARG_SHARED) $(LIBRUBYARG_STATIC) -lm -lruby2 -lc\n"
    assert_equal %w[-L/b -L/usr/local/lib -Wl,-rpath,/usr/local/lib -L/usr/local/lib -lm -lruby2 -lc],
                 Zr::Ext::Makefile.new(text, dir: "/b").libraries
  end

  # mkmf's template alone is standard, also with a depend file's header
  # lines; a rule of the extconf's own is not.
  def test_a_makefile_is_standard_when_its_rules_are_mkmfs
    assert_predicate makefile, :standard?
    headers = "#{MAKEFILE}a.o: $(HDRS) hello.h\n$(OBJS): $(ruby_headers)\n.c.o:\n\t$(CC) -c $<\n"
    assert_predicate Zr::Ext::Makefile.new(headers, dir: "/b"), :standard?
    own = "#{MAKEFILE}build-libffi $(LIBFFI_A):\n\t$(MAKE) -C libffi\n"
    refute_predicate Zr::Ext::Makefile.new(own, dir: "/b"), :standard?
  end

  # The bundles that the host's install built, in the gem's extension
  # directory, are found where a require under the gem's lib/ looks.
  def test_an_install_without_objects_gives_the_bundles_that_it_built
    Dir.mktmpdir do |root|
      gem = File.join(root, "gem")
      built = File.join(root, "extensions", "gem")
      FileUtils.mkdir_p([File.join(gem, "ext", "hello"), File.join(built, "json", "ext"), File.join(built, "x.bundle.dSYM", "y")])
      File.write(File.join(gem, "ext", "hello", "Makefile"), MAKEFILE)
      %w[top.bundle json/ext/parser.bundle x.bundle.dSYM/y/x.bundle].each { |name| File.write(File.join(built, name), "") }
      sources = Zr::Ext::Source.installed(gem, built)

      assert_equal [["json/ext/parser.bundle", "Init_parser"], ["top.bundle", "Init_top"]],
                   sources.map { |s| [s.bundle.delete_prefix("#{gem}/lib/"), s.init] }
      assert_equal [File.join(built, "json/ext/parser.bundle"), :embed], [sources.first.library, sources.first.mode]
    end
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
      ["3.4", Zr::Ext::ABI].each do |abi|
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

  # A default gem's C is in ruby's arch directory, where ruby's require
  # finds it: the bundles that the gem's files or its extconf.rb
  # directories name, and only those that are there.
  def test_a_default_gem_gives_the_bundles_of_ruby_s_arch_directory
    dlext = RbConfig::CONFIG["DLEXT"]
    archdir = RbConfig::CONFIG["archdir"]
    skip "ruby has no stringio.#{dlext} in #{archdir}" unless File.file?(File.join(archdir, "stringio.#{dlext}"))

    sources = Zr::Ext::Source.archdir(["lib/stringio.rb", "stringio.#{dlext}"], ["ext/stringio/extconf.rb", "ext/nothing_here/extconf.rb"])

    assert_equal [File.join(archdir, "stringio.#{dlext}")], sources.map(&:bundle)
    assert_equal ["Init_stringio", :embed, sources.first.bundle], [sources.first.init, sources.first.mode, sources.first.library]
  end

  # An ELF binary, static or dynamic, links only objects, so a default
  # gem whose C ruby compiled into a library has no C for it: the build
  # refuses, and a port that puts the gem's C first stands in
  # (`Ext.bundles`).
  def test_an_elf_target_takes_no_compiled_library_of_a_default_gem
    dlext = RbConfig::CONFIG["DLEXT"]
    skip "ruby has no stringio.#{dlext}" unless File.file?(File.join(RbConfig::CONFIG["archdir"], "stringio.#{dlext}"))

    %i[static dynamic].each do |link|
      elf = Zr::Target.default.with(object_format: :elf, link: link)
      error = assert_raises(Zr::Refused, link.to_s) { Zr::Ext.installed("stringio", nil, target: elf) }
      assert_includes error.message, "has no C extension"
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
    assert_includes names, "rb_tracearg_callee_id"
    refute_includes names, "zr_capi_str", "a kernel helper is not C API"
    assert_includes names, "OnigEncodingASCII", "Onigmo's data is ruby's"
    refute_includes names, "zr_capi_verbose", "a word of zr's own is not C API"
    assert_equal %w[rb_not_a_function], Zr::Ext::CApi.missing(%w[rb_define_method memcpy rb_not_a_function rb_raise])
    assert_equal %w[OnigEncodingNone], Zr::Ext::CApi.missing(%w[OnigEncodingASCII OnigEncodingNone])
  end

  # An extension's own global with a ruby-like name (zstd-ruby's
  # `rb_cCDict`), defined in one object and used in another, is not an
  # import of the extension.
  def test_a_name_that_one_object_defines_is_not_an_import_of_the_others
    skip "needs an aarch64-apple-darwin host" unless Zr::Target::AARCH64_DARWIN.native?

    Dir.mktmpdir do |dir|
      sources = { "defines" => "unsigned long rb_cOwn;\n",
                  "uses" => "extern unsigned long rb_cOwn;\nunsigned long rb_intern(const char *);\n" \
                            "unsigned long Init_uses(void) { return rb_cOwn + rb_intern(\"x\"); }\n" }
      objects = sources.map do |name, c|
        File.write(File.join(dir, "#{name}.c"), c)
        system("cc", "-c", File.join(dir, "#{name}.c"), "-o", File.join(dir, "#{name}.o"), exception: true)
        File.join(dir, "#{name}.o")
      end

      assert_equal %w[rb_cOwn rb_intern], Zr::Ext::CApi.imports(objects.last).sort
      assert_equal %w[rb_intern], Zr::Ext::CApi.imports(*objects)
      Zr::Ext::CApi.check!([Zr::Ext::Source.given(File.join(dir, "uses.bundle"), objects)])
    end
  end

  # The features that an extension's C may require are its C strings that
  # read as feature names, and only when it imports a require function.
  def test_an_extension_requires_the_feature_names_in_its_c_strings
    skip "needs an aarch64-apple-darwin host" unless Zr::Target::AARCH64_DARWIN.native?

    Dir.mktmpdir do |dir|
      sources = { "requires" => "void rb_require(const char *);\nint puts(const char *);\n" \
                                "void Init_requires(void) { rb_require(\"demo/part\"); rb_require(\"set\"); puts(\"Not a Feature!\"); }\n",
                  "quiet" => "int puts(const char *);\nvoid Init_quiet(void) { puts(\"demo/part\"); }\n" }
      found = sources.to_h do |name, c|
        File.write(File.join(dir, "#{name}.c"), c)
        object = File.join(dir, "#{name}.o")
        system("cc", "-c", File.join(dir, "#{name}.c"), "-o", object, exception: true)
        [name, Zr::Ext::Source.given(File.join(dir, "#{name}.bundle"), [object]).required_features]
      end

      assert_equal({ "requires" => %w[demo/part set], "quiet" => [] }, found)
    end
  end

  # An extension that hooks trace events (a C TracePoint, or a debugger's
  # frames) traces, and the program that requires it is built with its
  # trace events armed, though no file names TracePoint. An extension
  # that hooks none leaves the program untraced.
  def test_an_extension_that_hooks_trace_events_arms_them_in_the_program
    skip "needs an aarch64-apple-darwin host" unless Zr::Target::AARCH64_DARWIN.native?

    Dir.mktmpdir do |dir|
      lib = File.join(dir, "lib")
      FileUtils.mkdir_p(lib)
      sources = { "point" => "void *rb_tracepoint_new(unsigned long, unsigned, void *, void *);\n" \
                             "void Init_point(void) { rb_tracepoint_new(0, 8, 0, 0); }\n",
                  "frames" => "void *rb_debug_inspector_open(void *, void *);\nvoid Init_frames(void) { rb_debug_inspector_open(0, 0); }\n",
                  "quiet" => "unsigned long rb_intern(const char *);\nvoid Init_quiet(void) { rb_intern(\"x\"); }\n" }
      given = sources.to_h do |name, c|
        File.write(File.join(dir, "#{name}.c"), c)
        object = File.join(dir, "#{name}.o")
        system("cc", "-c", File.join(dir, "#{name}.c"), "-o", object, exception: true)
        [name, "#{File.join(lib, "#{name}.bundle")}=#{object}"]
      end

      Zr::Config.with(ZR_EXT_OBJECTS: given.values.join(" ")) do
        assert_equal({ "point" => true, "frames" => true, "quiet" => false },
                     Zr::Ext.bundles.select { |path, _| path.start_with?("#{lib}/") }
                       .to_h { |path, source| [File.basename(path, ".bundle"), source.traces?] })
      end
      # Each program links the one extension that it is given, which a
      # computed require may load as well as a literal one.
      traced = given.to_h do |name, ext|
        Zr::Config.with(ZR_EXT_OBJECTS: ext) do
          [name, Zr::Hir::Build.program("require #{name.dump}\n", File.join(dir, "main.rb"), roots: [lib], extensions: Zr::Ext).traced]
        end
      end

      assert_equal({ "point" => true, "frames" => true, "quiet" => false }, traced)
    end
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

  # A program's require finds the C extension that its build links; eval
  # support, which every program shares and the cache keeps, never does,
  # or a build with --native-ext would leave its extension in the cache.
  def test_only_a_programs_loader_finds_the_linked_extensions
    Dir.mktmpdir do |dir|
      lib = File.join(dir, "lib")
      bundle = File.join(lib, "hello.bundle")
      Zr::Config.with(ZR_EXT_OBJECTS: bundle) do
        program = Zr::Hir::Build::Loader.new([lib], extensions: Zr::Ext)
        support = Zr::Hir::Build::Loader.new([lib])

        assert_equal bundle, program.resolve(:require, "hello", File.join(dir, "main.rb"))
        assert_nil support.resolve(:require, "hello", File.join(dir, "main.rb"))
      end
    end
  end
end
