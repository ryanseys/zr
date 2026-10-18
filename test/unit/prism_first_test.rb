# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require_relative "../support/prism_first"

# Which prism the tests load first (test/support/prism_first.rb): ruby's
# own while it is zr's, else zr's.
class PrismFirstTest < Minitest::Test
  OURS = File.join(Zr::Test::PrismFirst::LIB, "prism/node.rb")

  def test_a_copy_of_zr_s_prism_is_the_same
    first_on_the_load_path(File.binread(OURS)) { assert Zr::Test::PrismFirst.same?(OURS) }
  end

  def test_another_prism_of_the_same_size_is_not
    bytes = File.binread(OURS)
    bytes[-2] = bytes[-2] == "a" ? "b" : "a"
    first_on_the_load_path(bytes) { refute Zr::Test::PrismFirst.same?(OURS) }
  end

  def test_an_older_prism_is_not
    first_on_the_load_path("module Prism; end\n") { refute Zr::Test::PrismFirst.same?(OURS) }
  end

  private

  # Runs the block with a prism/node.rb of `bytes` first on the load path.
  def first_on_the_load_path(bytes)
    Dir.mktmpdir do |dir|
      Dir.mkdir(File.join(dir, "prism"))
      File.binwrite(File.join(dir, "prism/node.rb"), bytes)
      $LOAD_PATH.unshift(dir)
      yield
    ensure
      $LOAD_PATH.delete(dir)
    end
  end
end
