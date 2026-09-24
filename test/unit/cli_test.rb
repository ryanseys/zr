# frozen_string_literal: true

require "test_helper"
require "stringio"
require_relative "../../lib/zr/cli"

# The command builds only on the one pinned ruby version. A build reads
# the standard library of that ruby, and the tests check zr against the
# output of that ruby.
class CliTest < Minitest::Test
  def test_pinned_ruby_matches_ruby_version_file
    assert_equal File.read(File.expand_path("../../.ruby-version", __dir__)).strip, Zr::RUBY
  end

  def test_the_pinned_ruby_builds
    assert_nil Zr::CLI.host_refusal(Zr::RUBY)
  end

  def test_other_ruby_is_refused_with_message
    assert_equal "zr #{Zr::VERSION} builds on ruby #{Zr::RUBY}, the ruby .ruby-version pins; this is ruby 4.0.7",
                 Zr::CLI.host_refusal("4.0.7")
  end

  def test_a_build_on_another_ruby_stops_with_the_refusal_status
    error = assert_raises(SystemExit) do
      assert_output(nil, "zr: #{Zr::CLI.host_refusal("4.0.7")}\n") { Zr::CLI.pinned!("4.0.7") }
    end
    assert_equal Zr::CLI::REFUSED, error.status
    assert_nil Zr::CLI.pinned!(Zr::RUBY)
  end
end

# How `zr` reads its command line, and what it says when it cannot.
class CliParseTest < Minitest::Test
  CLI = Zr::CLI

  def test_run_gives_every_word_after_the_file_to_the_program
    opts = CLI.parse("run", %w[app.rb -n 5 --x])

    assert_equal "app.rb", opts[:input]
    assert_equal %w[-n 5 --x], opts[:args]
  end

  def test_run_reads_options_before_the_file
    opts = CLI.parse("run", %w[--emit wasm --target=wasm32-wasi app.rb a])

    assert_equal "wasm", opts[:emit]
    assert_equal "wasm32-wasi", opts[:triple]
    assert_equal %w[a], opts[:args]
  end

  def test_a_double_dash_before_the_file_ends_the_options
    assert_equal ["-app.rb", ["a"]], CLI.parse("run", %w[-- -app.rb a]).values_at(:input, :args)
  end

  def test_build_reads_options_after_the_file
    opts = CLI.parse("build", %w[app.rb -o app --emit obj])

    assert_equal ["app.rb", "app", "obj"], opts.values_at(:input, :output, :emit)
  end

  def test_emit_binary_is_the_default_kind
    assert_nil CLI.parse("build", %w[app.rb -o app --emit binary])[:emit]
  end

  def test_usage_errors_print_one_line_and_exit_2
    {
      %w[run] => "zr run: missing <file.rb>",
      %w[run -o x app.rb] => "zr run: -o does not apply; use 'zr build' to keep the output",
      %w[run --emit obj app.rb] => "zr run: cannot run an object file; use 'zr build --emit obj'",
      %w[build app.rb] => "zr build: missing -o <path>",
      %w[build app.rb -o app extra] => "zr build: unexpected argument 'extra'",
      %w[build --emit=elf app.rb -o app] => "zr build: unknown --emit 'elf'; use binary, obj or wasm",
      %w[build --path-root rel app.rb -o app] => "zr build: --path-root needs an absolute path",
      %w[build --bogus app.rb -o app] => "zr build: unknown option '--bogus'",
      %w[build app.rb -o] => "zr build: -o needs a path"
    }.each do |(command, *args), line|
      _, err = assert_exit(2) { CLI.parse(command, args) }
      assert_equal "#{line}\nRun 'zr help #{command}' for usage.\n", err, args.inspect
    end
  end

  def test_an_unknown_command_exits_2
    _, err = assert_exit(2) { CLI.start(%w[compile app.rb]) }

    assert_equal "zr: unknown command 'compile'\nRun 'zr help' for usage.\n", err
  end

  def test_no_command_prints_the_usage_on_stderr_and_exits_2
    _, err = assert_exit(2) { CLI.start([]) }

    assert_match(/\AUsage: zr <command>/, err)
  end

  def test_help_for_a_command_prints_its_options_and_exits_0
    out, = assert_exit(0) { CLI.start(%w[build --help]) }

    assert_match(/\AUsage: zr build/, out)
    assert_match(/-o, --output/, out)
    assert_equal CLI::HELP.fetch("run"), capture_io { CLI.start(%w[help run]) }.first
  end

  def test_a_missing_file_prints_one_line_and_exits_1
    _, err = assert_exit(1) { CLI.start(%w[run no_such_file.rb]) }

    assert_equal "zr: no such file: no_such_file.rb\n", err
  end

  def test_targets_prints_a_row_for_each_target
    out, = capture_io { CLI.start(%w[targets]) }
    lines = out.lines

    assert_match(/\ATARGET\s+OUTPUTS\s+ON THIS HOST$/, lines.first)
    assert_equal Zr::Target.all.map(&:triple), lines.drop(1).map { |line| line.split.first }
  end

  private

  # Returns the stdout and stderr of the block. The block must exit with
  # `status`.
  def assert_exit(status)
    out, err = $stdout, $stderr
    $stdout, $stderr = StringIO.new, StringIO.new
    error = assert_raises(SystemExit) { yield }
    assert_equal status, error.status
    [$stdout.string, $stderr.string]
  ensure
    $stdout, $stderr = out, err
  end
end
