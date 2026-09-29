# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "zr/runtime"

# Eval support carries the kernel's description as a generated file. A
# build checks it before eval support is lowered: in a checkout, zr writes
# a stale file again, because a stale file miscompiles evals with no error.
class CarriedDescriptionTest < Minitest::Test
  def setup
    @runtime = Zr.runtime(Zr::Target.default)
    @want = Zr::Machine::Description.carried(@runtime.send(:cached).fetch(:description))
    @checkout = @runtime.carried_description
    @dir = Dir.mktmpdir("zr-carried-")
    @path = File.join(@dir, "zr_description.rb")
    path = @path
    @runtime.singleton_class.define_method(:carried_description) { path }
  end

  def teardown
    @runtime.singleton_class.remove_method(:carried_description)
    FileUtils.rm_rf(@dir)
  end

  def test_the_checkout_file_is_current
    assert_equal @want, File.binread(@checkout), "run `zr-dev gen description`"
  end

  def test_a_stale_file_is_written_again_in_a_checkout
    File.write(@path, "# stale\n")
    _, err = capture_io { @runtime.carry_description! }

    assert_equal @want, File.binread(@path)
    assert_match(/was out of date with runtime\/kernel; zr wrote it again/, err)
  end

  def test_a_current_file_is_left_as_it_is
    File.write(@path, @want)
    before = File.mtime(@path)
    _, err = capture_io { @runtime.carry_description! }

    assert_equal before, File.mtime(@path)
    assert_empty err
  end
end
