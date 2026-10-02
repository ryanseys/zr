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
# as it starts.
host = ENV["ZR_TEST_HOST"] == "1"
if host
  require "pathname"
  require_relative "../tool/hosted"
  stacks = Zr::Dev::Hosted::STACK
  unless stacks.all? { |name, value| ENV[name] == value }
    # bin/minitest requires each file as `./<path>`, from here.
    file = Pathname(__FILE__).relative_path_from(Dir.pwd).to_s
    exec(stacks, RbConfig.ruby, "--yjit", $PROGRAM_NAME, file, *ARGV)
  end
end

require_relative "test_helper"
require_relative "support/programs"
require_relative "support/host_program" if host

class ProgramsTest < Minitest::Test
  PROGRAMS = Zr::Test::Programs.new(host: ENV["ZR_TEST_HOST"] == "1")
  CASES = Zr::Test::Programs.cases.to_h { |test| ["test_#{test.rel}", test] }

  # Why zr did not build or run a program: a test error, not a failure.
  class NotBuilt < StandardError; end

  # Before the workers fork: the host walks the core once, and a build
  # gets the runtime (and eval support, when a selected program evals).
  def self.minitest_plugin_init(options)
    selected = filter_runnable_methods(options).map { |name| CASES.fetch(name) }
    return if selected.empty?

    if PROGRAMS.host?
      Zr::Test::HostProgram.walk
    else
      Zr::Test::Built.ready_for_programs!(selected)
    end
  end

  CASES.each do |name, test|
    define_method(name) do
      kind, detail = PROGRAMS.check(test)
      case kind
      when :skip then skip(detail)
      when :fail then flunk(detail)
      when :error then raise NotBuilt, detail, ["#{test.path}:1"]
      else pass
      end
    end
  end
end

Minitest.register_plugin(ProgramsTest)
