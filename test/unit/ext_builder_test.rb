# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require_relative "../../lib/zr/ext"

# `Ext::Builder`: an extension built from its extconf.rb, as `gem install`
# builds one, into the store. mkmf's Makefile alone is compiled with cc
# for each source; a Makefile with rules of its own runs under make.
class ExtBuilderTest < Minitest::Test
  SOURCE = <<~C
    #include <ruby.h>
    #include "helper.h"
    static VALUE answer(VALUE self) { return INT2FIX(HELPER_ANSWER); }
    void Init_tiny(void) { rb_define_module_function(rb_define_module("Tiny"), "answer", answer, 0); }
  C

  def setup
    skip "needs an aarch64-apple-darwin host" unless Zr::Target::AARCH64_DARWIN.native?
    @gem = Dir.mktmpdir
    @ext = File.join(@gem, "ext", "tiny")
    FileUtils.mkdir_p(@ext)
    File.write(File.join(@ext, "tiny.c"), SOURCE)
    # The digest of the sources keys the build: each test has its own.
    File.write(File.join(@ext, "helper.h"), "#define HELPER_ANSWER 42 /* #{@gem} */\n")
  end

  def teardown
    FileUtils.rm_rf(@gem) if @gem
  end

  def extconf(text)
    path = File.join(@ext, "extconf.rb")
    File.write(path, text)
    path
  end

  def test_mkmfs_makefile_compiles_each_source_with_cc
    builder = Zr::Ext::Builder.new(extconf(%(require "mkmf"\ncreate_makefile("tiny/tiny")\n)))
    source = builder.source(@gem)

    assert_equal [File.join(@gem, "lib", "tiny", "tiny.bundle"), "Init_tiny", :static], [source.bundle, source.init, source.mode]
    assert_equal [File.join(builder.build, "tiny.o")], source.objects
    assert(source.objects.all? { |object| File.file?(object) })
    refute_path_exists File.join(builder.build, "tiny.bundle"), "cc compiles; the link of the bundle is zr's"
    assert_includes Zr::Obj::MachO::Image.read(File.binread(source.objects.first)).undefined, "_rb_define_module_function"
  end

  def test_the_same_sources_and_arguments_build_once
    path = extconf(%(require "mkmf"\ncreate_makefile("tiny")\n))
    first = Zr::Ext::Builder.new(path).build
    stamp = File.mtime(File.join(first, "tiny.o"))

    assert_equal first, Zr::Ext::Builder.new(path).build
    assert_equal stamp, File.mtime(File.join(first, "tiny.o"))
    refute_equal first, Zr::Ext::Builder.new(path, args: ["--with-tiny-dir=/none"]).build
  end

  def test_a_makefile_with_rules_of_its_own_runs_under_make
    builder = Zr::Ext::Builder.new(extconf(<<~RUBY))
      require "mkmf"
      create_makefile("tiny")
      File.write("Makefile", File.read("Makefile") + "\\ngenerated.h:\\n\\techo '/* made */' > $@\\n$(OBJS): generated.h\\n")
    RUBY
    dir = builder.build

    assert File.file?(File.join(dir, "generated.h")), "make ran the extconf's rule"
    assert File.file?(File.join(dir, "tiny.o"))
    refute_predicate Zr::Ext::Makefile.read(File.join(dir, "Makefile")), :standard?
  end

  def test_a_failed_extconf_refuses_with_its_output
    builder = Zr::Ext::Builder.new(extconf(%(abort "no libtiny on this system #{@gem}"\n)))

    error = assert_raises(Zr::Refused) { builder.build }
    assert_match(/\Atiny: `ruby extconf\.rb` failed while zr built the C extension:\nno libtiny on this system/, error.message)
  end
end
