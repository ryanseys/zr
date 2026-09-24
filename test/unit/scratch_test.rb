# frozen_string_literal: true

require "test_helper"
require_relative "../support/scratch"

# A tier sweeps the temporary directories whose makers are gone
# (test/support/scratch.rb), and only those.
class ScratchTest < Minitest::Test
  def setup
    @root = Dir.mktmpdir("scratch-")
  end

  def teardown
    FileUtils.rm_rf(@root)
  end

  def test_a_directory_whose_maker_is_gone_is_swept
    gone = made_by(dead_pid)

    Zr::Test::Scratch.sweep(@root)

    refute File.exist?(gone)
  end

  def test_a_directory_whose_maker_lives_is_kept
    kept = made_by(Process.pid)

    Zr::Test::Scratch.sweep(@root)

    assert File.exist?(kept)
  end

  def test_a_directory_of_another_name_is_kept
    other = File.join(@root, "not-zr-20260923-#{dead_pid}-x")
    Dir.mkdir(other)

    Zr::Test::Scratch.sweep(@root)

    assert File.exist?(other)
  end

  private

  def made_by(pid)
    File.join(@root, "zr-bins-20260923-#{pid}-a1b2c3").tap do |dir|
      FileUtils.mkdir_p(File.join(dir, "4711"))
      File.write(File.join(dir, "4711", "p"), "x")
    end
  end

  def dead_pid
    pid = spawn("true")
    Process.wait(pid)
    pid
  end
end
