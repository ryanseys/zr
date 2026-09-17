# frozen_string_literal: true

require_relative "helper"
require_relative "../../lib/ze0/harness/prism_diff"

# The pure-Ruby prism held to ruby's C prism (tools/prism_diff.rb): its
# generated files current with the vendored config.yml and templates, and
# Prism.dump's writer equal to the C byte for byte on every dump read back.
class PrismTest < Minitest::Test
  PrismDiff = Ze0::Harness::PrismDiff

  def test_the_generated_files_are_current
    out = IO.popen([RbConfig.ruby, File.join(ROOT, "tools/prism_generate.rb"), "--check"], err: %i[child out], &:read)
    assert $?.success?, out
  end

  def test_the_writer_writes_ze0s_own_ruby_as_the_c_does
    cases = PrismDiff.cases(%w[rt lib])
    assert_operator cases.size, :>, 300
    assert_empty PrismDiff.writer(cases).first(5)
  end

  def test_the_writer_writes_prisms_fixtures_and_errors_as_the_c_does
    skip "no prism checkout at #{PrismDiff::CHECKOUT}" unless PrismDiff.upstream

    cases = PrismDiff.cases(%w[fixtures errors])
    assert_operator cases.size, :>, 5000
    assert_empty PrismDiff.writer(cases).first(5)
  end
end
