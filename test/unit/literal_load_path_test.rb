# frozen_string_literal: true

require "test_helper"
require_relative "../../lib/zr/hir"

# A program that adds a directory to $LOAD_PATH with a path the compiler
# can read resolves its requires at build time. Any other change links
# the compiler, so a require can find a file that was not compiled in.
class LiteralLoadPathTest < Minitest::Test
  LITERAL = [
    %($LOAD_PATH.unshift File.expand_path("../lib", __dir__)),
    %($LOAD_PATH.unshift File.expand_path("../lib", __FILE__)),
    %($LOAD_PATH.unshift File.join(__dir__, "lib")),
    %($LOAD_PATH.unshift File.join(File.dirname(__FILE__), "lib")),
    %($LOAD_PATH.unshift File.expand_path("lib", File.dirname(__FILE__))),
    %($LOAD_PATH << "\#{__dir__}/lib"),
    %($: << "\#{File.dirname(__FILE__)}/lib")
  ].freeze

  def test_a_literal_path_links_no_compiler
    LITERAL.each { |line| refute evals?(line), line }
  end

  def test_a_computed_path_links_the_compiler
    assert evals?(%($LOAD_PATH.unshift ENV.fetch("LIB", "lib")))
  end

  private

  # Whether the loader links the compiler for the only statement of `source`.
  def evals?(source)
    loader = Zr::Hir::Build::Loader.new([])
    call = Prism.parse(source).value.statements.body.first
    loader.load_path_changed!(call, "/nonexistent/app/main.rb")
    loader.evals?
  end
end
