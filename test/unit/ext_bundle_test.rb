# frozen_string_literal: true
# zr-test: on macho

require "test_helper"
require "tmpdir"
require_relative "../../lib/zr/native/build"

# `Native::Build.ext_bundle`: the bundle that zr's linker relinks into a
# binary. A static extension's objects link into a bundle that the store
# keeps; a precompiled bundle is used as it is.
class ExtBundleTest < Minitest::Test
  def setup
    skip "needs an aarch64-apple-darwin host" unless Zr::Target::AARCH64_DARWIN.native?
    @dir = Dir.mktmpdir
  end

  def teardown
    FileUtils.rm_rf(@dir) if @dir
  end

  #: (String name, String c) -> String
  def object(name, c)
    path = File.join(@dir, "#{name}.c")
    File.write(path, c)
    out = File.join(@dir, "#{name}.o")
    system("cc", "-c", path, "-o", out, exception: true)
    out
  end

  def source(objects, library: nil)
    Zr::Ext::Source.new(bundle: File.join(@dir, "tiny.bundle"), init: "Init_tiny", objects: objects, libraries: [], library: library,
                        mode: library ? :embed : :static)
  end

  def test_the_objects_link_into_a_bundle_that_the_store_keeps
    # The digest of the object is the key: each run gets its own entry.
    tiny = object("tiny", "unsigned long rb_intern(const char *);\nunsigned long Init_tiny(void) { return rb_intern(\"#{@dir}\"); }\n")
    path = Zr::Native::Build.ext_bundle(source([tiny]), Zr::Target::AARCH64_DARWIN)
    image = Zr::Obj::MachO::Image.read(File.binread(path))

    assert_includes image.exports.map(&:name), "_Init_tiny"
    assert_includes image.undefined, "_rb_intern"
    assert_equal path, Zr::Native::Build.ext_bundle(source([tiny]), Zr::Target::AARCH64_DARWIN)
    assert_equal ["#{path}.lock"], Dir["#{path}.*"], "the link leaves no part file"
  end

  def test_a_precompiled_bundle_is_used_as_it_is
    assert_equal "/x/tiny.bundle", Zr::Native::Build.ext_bundle(source([], library: "/x/tiny.bundle"), Zr::Target::AARCH64_DARWIN)
  end

  def test_objects_that_cc_cannot_link_refuse_the_build_with_its_message
    bad = File.join(@dir, "bad.o")
    File.write(bad, "not an object #{@dir}")

    error = assert_raises(Zr::Refused) { Zr::Native::Build.ext_bundle(source([bad]), Zr::Target::AARCH64_DARWIN) }
    assert_match(/\Acc cannot link tiny\.bundle from its objects:\n.*bad\.o/m, error.message)
  end
end
