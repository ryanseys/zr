# frozen_string_literal: true

require "test_helper"
require_relative "../../lib/zr/hir"

# A program that calls eval is built twice: first to find out that it
# calls eval, then again against the prebuilt eval support, which refers
# to each file it contains by its entry symbol and does not read it.
# The first build finds out at the first line that refers to Gem or calls
# eval. From that line on, it also refers to those files by entry symbol.
class EvalPrebuiltTest < Minitest::Test
  # Prebuilt eval support, as the loader sees it: the entry symbol of
  # each file that it contains, and its flags.
  class Prebuilt
    attr_reader :units

    def initialize(paths)
      @units = paths.each_with_index.to_h { |path, i| [path, "zr_eval_support_#{i}"] }
    end

    def normalizes? = false
    def pretty_prints? = false
    def irbs? = false
    def configures? = false
    def gems? = true
    def activations = 0
  end

  VENDOR = Zr::Library::Roots.pure
  HELD = (Dir[File.join(VENDOR, "rubygems/**/*.rb")] + Zr::Hir::Build.rubygems_files +
          Dir[File.join(ROOT, "lib/zr/**/*.rb")].reject { |path| path.match?(%r{/lib/zr/runtime/(kernel|core)/}) }).sort.freeze

  # The number of times the loader parses each file, by path.
  module Counting
    PARSED = Hash.new(0)

    def parse(source, **options)
      PARSED[options[:filepath]] += 1 if options[:filepath]
      super
    end
  end

  def test_first_build_skips_eval_support_files_after_eval_found
    Counting::PARSED.clear
    Zr.singleton_class.prepend(Counting) unless Zr.singleton_class < Counting
    program = Zr::Hir::Build.program("require \"rubygems\"\nputs Gem::VERSION\n", "probe.rb", prebuilt: Prebuilt.new(HELD))
    assert program.evals, "rubygems evals"

    parsed = Counting::PARSED.keys.select { |path| path.start_with?(File.join(VENDOR, "rubygems")) }
    assert_equal [], parsed, "files under rubygems/ read by the first build"
    # `require "rubygems"` itself shows that the program calls eval (the
    # prelude loads rubygems), so the build does not read rubygems.rb.
    assert_equal 0, Counting::PARSED[File.join(VENDOR, "rubygems.rb")]
    assert_equal 2, Counting::PARSED["probe.rb"], "the program is read by both builds"
  end
end
