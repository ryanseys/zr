# frozen_string_literal: true
# zr-test: eval

# The program tests: one test for each plain Ruby program below
# test/programs that has ruby's output beside it
# (test/support/program_case.rb). zr builds the program and runs it, and
# the test compares stdout, stderr and the exit status with ruby's.
#
#   bin/minitest test/programs_test.rb                     every program
#   ZR_PROGRAMS=core/gc,lang bin/minitest test/programs_test.rb
#                                                          the programs below those paths
#   bin/minitest test/programs_test.rb -i /stdlib.uri/     the tests whose name matches
#   ZR_TEST_HOST=1 bin/minitest test/programs_test.rb      on CRuby over zr's kernel, with
#                                                          no build (test/baselines/host.txt)
#
# The walker of the host nests Ruby frames, so a host run starts ruby
# again with the stacks and YJIT of `zr-dev host`. ruby reads both only
# as it starts. A host test that passed before with the same inputs
# passes again at once (test/support/result_cache.rb; ZR_TEST_FRESH=1
# runs each one).
host = ENV["ZR_TEST_HOST"] == "1"
if host
  require_relative "../tool/hosted"
  stacks = Zr::Dev::Commands::Hosted::STACK
  unless stacks.all? { |name, value| ENV[name] == value }
    # bin/minitest requires each file as `./<path>`, from here.
    file = Pathname(__FILE__).relative_path_from(Dir.pwd).to_s
    exec(stacks, RbConfig.ruby, "--yjit", $PROGRAM_NAME, file, *ARGV)
  end
end

require_relative "test_helper"
require_relative "support/programs"
require_relative "support/result_cache"
require_relative "support/host_program" if host

class ProgramsTest < Minitest::Test
  PROGRAMS = Zr::Test::Programs.new(host: ENV["ZR_TEST_HOST"] == "1")
  CASES = Zr::Test::Programs.cases.to_h { |test| ["test_#{test.rel}", test] }
  RESULTS = (Zr::Test::ResultCache.new if PROGRAMS.host? && Zr::Test::ResultCache.enabled?)

  # Why zr did not build or run a program: a test error, not a failure.
  class NotBuilt < StandardError; end

  # Counts the host tests that passed from the result cache.
  class Cached < Minitest::AbstractReporter
    def initialize(io)
      super()
      @io = io
      @count = 0
    end

    def record(result)
      @count += 1 if result.metadata[:cached]
    end

    def report
      @io.puts "\n#{@count} of the passes came from the result cache (ZR_TEST_FRESH=1 runs them)" if @count.positive?
    end
  end

  # Before the workers fork: the host walks the core once (unless each
  # selected test passes from the result cache). A build first trims the
  # kept binaries to their quota, then gets the runtime (and eval
  # support, when a selected program evals).
  def self.minitest_plugin_init(options)
    selected = filter_runnable_methods(options).map { |name| CASES.fetch(name) }
    return if selected.empty?

    if PROGRAMS.host?
      Minitest.reporter << Cached.new(options[:io]) if RESULTS
      Zr::Test::HostProgram.walk unless RESULTS && selected.all? { |test| RESULTS.passed?(test, PROGRAMS.baseline(test)) }
    else
      Zr::Test::Binaries.trim
      Zr::Test::Built.ready_for_programs!(selected)
    end
  end

  CASES.each do |name, test|
    define_method(name) do
      if RESULTS&.passed?(test, PROGRAMS.baseline(test))
        metadata[:cached] = true
        next pass
      end

      kind, detail = PROGRAMS.check(test)
      case kind
      when :skip then skip(detail)
      when :fail then flunk(detail)
      when :error then raise NotBuilt, detail, ["#{test.path}:1"]
      else
        RESULTS&.pass!(test, PROGRAMS.baseline(test))
        pass
      end
    end
  end
end

Minitest.register_plugin(ProgramsTest)
