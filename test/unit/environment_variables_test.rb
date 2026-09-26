# frozen_string_literal: true

require "test_helper"

# docs/reference/environment-variables.md lists every `ZR_*` variable
# that zr, its runtime, its tools and its tests read, and no other.
class EnvironmentVariablesTest < Minitest::Test
  DOC = File.read(File.join(ROOT, "docs/reference/environment-variables.md"))

  # Names that a test gives to its own child or program, not settings.
  NOT_SETTINGS = %w[ZR_TEST_AOT_SMOKE ZR_TEST_AOT_SMOKE_MISSING ZR_POOL_PID ZR_POOL_PIDS].freeze

  def read_by_code
    dirs = %w[lib bin tool exe runtime test/support test/unit test/test_helper.rb test/spec_helper.rb Rakefile]
    text = IO.popen(["git", "-C", ROOT, "grep", "-ohE", "ZR_[A-Z0-9_]+", "--", *dirs], &:read)
    text.split("\n").uniq.sort - NOT_SETTINGS
  end

  def documented = DOC.scan(/`(ZR_[A-Z0-9_]+)/).flatten.uniq.sort

  def test_every_variable_the_code_reads_is_documented
    assert_equal [], read_by_code - documented
  end

  def test_every_documented_variable_is_read
    assert_equal [], documented - read_by_code
  end
end
