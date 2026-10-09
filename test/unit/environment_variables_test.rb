# frozen_string_literal: true

require "test_helper"
require_relative "../../lib/zr/config"

# docs/reference/environment-variables.md lists every `ZR_*` variable
# that zr, its runtime, its tools and its tests read, and no other.
class EnvironmentVariablesTest < Minitest::Test
  DOC = File.read(File.join(ROOT, "docs/reference/environment-variables.md"))

  # Names that a test gives to its own child or program, not settings.
  # A prefix that code matches to find a group of variables
  # (test/support/result_cache.rb) is not a variable either, nor is a
  # macro in a C fixture (test/unit/c_scan_test.rb). `Ext::Builder` gives
  # ZR_TARGET_CC and the others to the ruby that runs an extconf.rb for another
  # target (lib/zr/ext/target_rbconfig.rb).
  NOT_SETTINGS = %w[ZR_TEST_AOT_SMOKE ZR_TEST_AOT_SMOKE_MISSING ZR_POOL_PID ZR_POOL_PIDS ZR_GC_ ZR_SCAN_LIB
                    ZR_SCAN_TEST_UNKNOWN ZR_TARGET_AR ZR_TARGET_CC ZR_TARGET_CXX ZR_TARGET_LIBDIR ZR_TARGET_RBCONFIG].freeze

  def read_by_code
    dirs = %w[lib bin tool exe test/support test/unit test/test_helper.rb Rakefile]
    text = IO.popen(["git", "-C", ROOT, "grep", "-ohE", "ZR_[A-Z0-9_]+", "--", *dirs], &:read)
    text.split("\n").uniq.sort - NOT_SETTINGS
  end

  def documented = DOC.scan(/`(ZR_[A-Z0-9_]+)/).flatten.uniq.sort

  def test_every_variable_the_code_reads_is_documented
    assert_equal [], read_by_code - documented
  end

  # The row of each setting gives its flag.
  def test_each_setting_gives_its_flag
    Zr::Config::SETTINGS.each do |setting|
      row = DOC.lines.find { |line| line.start_with?("| `#{setting.env}` |") }

      assert row, "#{setting.env} has no row"
      assert_includes row.split("|")[2], "`#{setting.flag}", setting.env
    end
  end

  def test_every_documented_variable_is_read
    assert_equal [], documented - read_by_code
  end
end
