# frozen_string_literal: true

require_relative "helper"
require_relative "../../lib/ze0/harness/prism_diff"

# The pure-Ruby prism held to ruby's C prism (tools/prism_diff.rb): its
# generated files current with the vendored config.yml and templates, and
# Prism.dump's writer equal to the C byte for byte on every dump read back,
# and the parser's dumps equal to the C's.
class PrismTest < Minitest::Test
  PrismDiff = Ze0::Harness::PrismDiff

  def test_the_generated_files_are_current
    out = IO.popen([RbConfig.ruby, File.join(ROOT, "tools/prism_generate.rb"), "--check"], err: %i[child out], &:read)
    assert $?.success?, out
    out = IO.popen([RbConfig.ruby, File.join(ROOT, "tools/prism_encoding_tables.rb"), "--check"], err: %i[child out], &:read)
    assert $?.success?, out
  end

  def test_the_writer_writes_ze0s_own_ruby_as_the_c_does
    cases = PrismDiff.cases(%w[rt lib])
    assert_operator cases.size, :>, 300
    assert_empty PrismDiff.writer(cases).first(5)
  end

  # The lexer with no parser behind it: every fixture and error file lexes
  # in every mode and gives C's tokens, except where the parser moves the
  # lex state (lambda braces, `do` loops, labels, ignored newlines,
  # interpolation), and none raises.
  def test_the_lexer_alone_lexes_prisms_fixtures_and_errors_as_the_c_does
    skip "no prism checkout at #{PrismDiff::CHECKOUT}" unless PrismDiff.upstream

    cases = PrismDiff.cases(%w[fixtures errors])
    failures, unsupported = PrismDiff.lex(cases)
    assert_empty failures.select { |_, why| why.include?("Error") }.first(5)
    assert_equal 0, unsupported
    assert_operator cases.size - failures.size, :>=, 4744
  end

  # The Ruby parser: Prism::Ruby.dump equal to Prism.dump byte for byte, on
  # ze0's own Ruby and on every fixture and error file under each syntax
  # version.
  def test_the_parser_dumps_ze0s_own_ruby_as_the_c_does
    cases = PrismDiff.cases(%w[rt lib])
    assert_operator cases.size, :>, 300
    assert_empty PrismDiff.dump(cases).first(5)
  end

  def test_the_parser_dumps_prisms_fixtures_and_errors_as_the_c_does
    skip "no prism checkout at #{PrismDiff::CHECKOUT}" unless PrismDiff.upstream

    cases = PrismDiff.cases(%w[fixtures errors])
    assert_operator cases.size, :>, 5000
    assert_empty PrismDiff.dump(cases).first(5)
  end

  def test_the_writer_writes_prisms_fixtures_and_errors_as_the_c_does
    skip "no prism checkout at #{PrismDiff::CHECKOUT}" unless PrismDiff.upstream

    cases = PrismDiff.cases(%w[fixtures errors])
    assert_operator cases.size, :>, 5000
    assert_empty PrismDiff.writer(cases).first(5)
  end
end
