# frozen_string_literal: true
# zr-test: runtime

require "test_helper"
require_relative "../support/c_ext"

# A C extension that requires Ruby files as its Init runs (`rb_require`),
# as oj and google-protobuf do: the build finds the features in its C
# strings and compiles them in, so the require finds them, as in ruby.
class CExtRequiresTest < Minitest::Test
  SOURCE = <<~'C'
    #include <ruby.h>

    static VALUE late(VALUE self) {
      rb_require("needs/late");
      return rb_funcall(rb_path2class("Late"), rb_intern("hello"), 0);
    }

    void Init_needs(void) {
      rb_require("needs/early");
      rb_require("set");
      VALUE m = rb_define_module("Needs");
      rb_define_module_function(m, "late", late, 0);
      rb_define_const(m, "EARLY", rb_funcall(rb_path2class("Early"), rb_intern("value"), 0));
    }
  C

  PROGRAM = <<~'RUBY'
    require "needs"
    p Needs::EARLY, defined?(Set), $LOADED_FEATURES.grep(/needs\/early/).size
    p Needs.late, Needs.late
    p $LOADED_FEATURES.grep(/needs\/late/).size
  RUBY

  FILES = {
    "needs/early.rb" => "module Early\n  def self.value = [:early, 1 + 1]\nend\n",
    "needs/late.rb" => "module Late\n  def self.hello = \"late #{1 + 1}\"\nend\n"
  }.freeze

  def setup
    skip "needs an aarch64-apple-darwin host" unless Zr::Target::AARCH64_DARWIN.native?
    @ext = Zr::Test::CExt.build("needs", SOURCE)
    FILES.each do |name, text|
      path = File.join(@ext.dir, name)
      FileUtils.mkdir_p(File.dirname(path))
      File.write(path, text)
    end
  end

  # debug_inspector's lib requires its bundle by a computed name: the
  # build links each extension that it is given, and require finds it by
  # any of its names, as ruby's does.
  COMPUTED = <<~'PROGRAM'
    require "rbconfig"
    name = "needs.#{RbConfig::CONFIG["DLEXT"]}"
    p require(name), require("needs"), require("needs.so")
    p Needs::EARLY, $LOADED_FEATURES.grep(/needs\.bundle\z/).size
    begin
      require "nothing.#{RbConfig::CONFIG["DLEXT"]}"
    rescue LoadError => e
      p e.message
    end
  PROGRAM

  def test_a_computed_name_finds_the_linked_extension
    ruby, zr = Zr::Test::CExt.outputs(@ext, COMPUTED)

    assert_equal 0, ruby.status, "ruby failed:\n#{ruby.stderr}"
    assert_equal [ruby.stdout, ruby.status], [zr.stdout, zr.status], "zr stderr:\n#{zr.stderr}"
  end

  def test_the_files_that_c_requires_load_as_in_ruby
    ruby, zr = Zr::Test::CExt.outputs(@ext, PROGRAM)

    assert_equal 0, ruby.status, "ruby failed:\n#{ruby.stderr}"
    assert_equal [ruby.stdout, ruby.status], [zr.stdout, zr.status], "zr stderr:\n#{zr.stderr}"
  end
end
