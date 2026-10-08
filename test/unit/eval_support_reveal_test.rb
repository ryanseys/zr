# frozen_string_literal: true
# zr-test: eval

require "test_helper"
require "open3"
require "tmpdir"

# A program that evals has zr's compiler in it, hidden from the program.
# When the program requires one of the compiler's files itself, as the
# compiler does when zr compiles zr, what that file defines becomes
# visible. hir/switches.rb reopens Zr::Hir, which another file of the
# compiler makes first: the reveal must find Hir inside Zr, not on Object.
class EvalSupportRevealTest < Minitest::Test
  EXE = File.join(ROOT, "exe/zr")
  SWITCHES = File.join(ROOT, "lib/zr/hir/switches.rb")

  def test_a_required_file_of_eval_support_shows_the_modules_it_reopens
    out = run_program(<<~RUBY)
      p eval("1 + 1")
      require #{SWITCHES.inspect}
      p defined?(Zr::Hir), Zr::Hir::Switches.name
      p Zr.constants.include?(:Hir), Object.const_defined?(:Hir)
    RUBY

    assert_equal %(2\n"constant"\n"Zr::Hir::Switches"\ntrue\nfalse\n), out
  end

  def test_what_the_program_did_not_require_stays_hidden
    out = run_program(<<~RUBY)
      p eval("1 + 1")
      require #{SWITCHES.inspect}
      p defined?(Zr::Lower), defined?(Zr::Hir::Build)
    RUBY

    assert_equal "2\nnil\nnil\n", out
  end

  private

  #: (String source) -> String
  def run_program(source)
    Dir.mktmpdir("zr-reveal-") do |dir|
      program = File.join(dir, "main.rb")
      File.write(program, source)
      out, err, status = Open3.capture3(EXE, "run", program)
      assert_predicate status, :success?, err
      out
    end
  end
end
