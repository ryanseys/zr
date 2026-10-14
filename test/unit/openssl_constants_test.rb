# frozen_string_literal: true

require "test_helper"
require "stringio"
require_relative "../../tool/gen/openssl_constants"

# The openssl port's Integer constants are the ones that the pinned ruby's
# openssl defines. `zr-dev gen openssl_constants` stays out of `gen all`,
# because the order of the constants depends on the OpenSSL build, so this
# test compares the lines as sets: a constant that is new, gone or of
# another value fails, and an order does not.
class OpensslConstantsTest < Minitest::Test
  PATH = File.join(ROOT, "lib/zr/runtime/ext/openssl/ossl/constants.rb")

  def setup
    skip "this is #{RUBY_DESCRIPTION}, not ruby #{Zr::RUBY_PIN}" unless Zr.pinned_ruby?
    require "openssl"
    headers = committed_headers
    skip "this ruby's openssl was built against #{OpenSSL::OPENSSL_VERSION}, not #{headers}" unless OpenSSL::OPENSSL_VERSION == headers
  end

  def committed_headers = File.read(PATH)[/OPENSSL_VERSION = "([^"]*)"/, 1]

  # The lines that define a constant, with no indent.
  def constants(text) = text.lines.map(&:strip).grep(/\A[\w:]+ = /).to_set

  def test_the_constants_are_the_ones_ruby_defines
    generated = StringIO.new
    Zr::Dev::Commands::Gen::OpensslConstants.new("gen openssl_constants").write(generated)
    committed = constants(File.read(PATH))
    written = constants(generated.string)

    assert_empty written - committed, "constants that ruby defines and #{PATH} lacks"
    assert_empty committed - written, "constants in #{PATH} that ruby does not define"
  end
end
