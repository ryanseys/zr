# frozen_string_literal: true

require "test_helper"
require_relative "../../lib/ze0/hir"

# A program that evals is built twice: once to learn that it evals, and
# once over the road, where every file the road holds is named by its
# entry and not read. The first build learns it at the first line that
# names Gem or evals, and from then on it too names the road's files:
# what it would read of them is thrown away with the rest of the pass.
# `require "rubygems"` used to read, parse and build rubygems' hundred
# files before naming them.
class RoadAheadTest < Minitest::Test
  # A road built already, as the loader sees one: the entry of every
  # file it holds, and its flags.
  class Road
    attr_reader :units

    def initialize(paths)
      @units = paths.each_with_index.to_h { |path, i| [path, "zr_road_#{i}"] }
    end

    def normalizes? = false
    def pretty_prints? = false
    def irbs? = false
    def configures? = false
    def gems? = true
    def activations = 0
  end

  VENDOR = Ze0::Hir::Build::VENDOR
  HELD = (Dir[File.join(VENDOR, "rubygems/**/*.rb")] + Ze0::Hir::Build::RUBYGEMS +
          Dir[File.join(ROOT, "lib/ze0/**/*.rb")] + Dir[File.join(ROOT, "rt/ext/**/*.rb")]).sort.freeze

  # The files the loader parses, by path, through the one road a parse
  # takes.
  module Counting
    PARSED = Hash.new(0)

    def parse(source, **options)
      PARSED[options[:filepath]] += 1 if options[:filepath]
      super
    end
  end

  def test_a_build_that_learns_it_evals_names_the_roads_files_from_then_on
    Counting::PARSED.clear
    Ze0.singleton_class.prepend(Counting) unless Ze0.singleton_class < Counting
    program = Ze0::Hir::Build.program("require \"rubygems\"\nputs Gem::VERSION\n", "probe.rb", road: Road.new(HELD))
    assert program.evals, "rubygems evals"

    parsed = Counting::PARSED.keys.select { |path| path.start_with?(File.join(VENDOR, "rubygems")) }
    assert_equal [], parsed, "files under rubygems/ read by the first build"
    # `require "rubygems"` itself says the program evals (the prelude
    # loads rubygems), so even rubygems.rb is named, not read.
    assert_equal 0, Counting::PARSED[File.join(VENDOR, "rubygems.rb")]
    assert_equal 2, Counting::PARSED["probe.rb"], "the program is read by both builds"
  end
end
