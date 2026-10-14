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
#                                                          (or anywhere; `bin/zr-dev test
#                                                          <path>` sets it)
#   bin/minitest test/programs_test.rb -i /stdlib.uri/     the tests whose name matches
#   ZR_TEST_HOST=1 bin/minitest test/programs_test.rb      on CRuby over zr's kernel, with
#                                                          no build (test/baselines/host.txt)
#
# The walker of the host nests Ruby frames, so a host run starts ruby
# again with the stacks and YJIT of `zr-dev host`
# (lib/zr/machine/host/launch.rb). ruby reads both only as it starts. A
# host test that passed before with the same inputs passes again at once
# (test/support/result_cache.rb; ZR_TEST_FRESH=1 runs each one).
require_relative "support/flag"
host = Zr::Test.flag?("ZR_TEST_HOST")
if host
  require_relative "../lib/zr/machine/host/launch"
  unless Zr::Machine::Host.stacked?
    # bin/minitest requires each file as `./<path>`, from here.
    file = Pathname(__FILE__).relative_path_from(Dir.pwd).to_s
    exec(Zr::Machine::Host::STACK, RbConfig.ruby, "--yjit", $PROGRAM_NAME, file, *ARGV)
  end
end

require_relative "test_helper"
require_relative "support/programs"
require_relative "support/result_cache"
require_relative "support/host_program" if host

class ProgramsTest < Minitest::Test
  PROGRAMS = Zr::Test::Programs.new(host: Zr::Test.flag?("ZR_TEST_HOST"))
  CASES = Zr::Test::ProgramSelection.cases.to_h { |test| ["test_#{Zr::Test::ProgramSelection.label(test)}", test] }
  RESULTS = (Zr::Test::ResultCache.new if Zr::Test::ResultCache.enabled?)

  # Why zr did not build or run a program: a test error, not a failure.
  class NotBuilt < StandardError; end

  # Before the workers fork, for the selected tests that do not pass
  # from the result cache: the host walks the core once, and a build
  # first trims the kept binaries to their quota, then gets the runtime
  # (and eval support, when such a program evals). When each one passes
  # from the cache, neither happens.
  def self.minitest_plugin_init(options)
    selected = filter_runnable_methods(options).map { |name| CASES.fetch(name) }
    return if selected.empty?

    left = RESULTS ? selected.reject { |test| RESULTS.passed?(test, PROGRAMS.baseline(test)) } : selected
    return if left.empty?

    if PROGRAMS.host?
      Zr::Test::HostProgram.walk
    else
      Zr::Test::Binaries.trim
      Zr::Test::Built.ready_for_programs!(left)
    end
  end

  CASES.each do |name, test|
    define_method(name) do
      if RESULTS&.passed?(test, PROGRAMS.baseline(test))
        metadata[:cached] = true
        next pass
      end

      # SLOW=1 reports the parts of each build (test/support/progress.rb).
      parts = (metadata[Zr::Test::Progress::PARTS_KEY] = {}) if Zr::Test::Progress.parts?
      kind, detail = PROGRAMS.check(test, parts: parts)
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
