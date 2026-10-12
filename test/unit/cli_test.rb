# frozen_string_literal: true

require "test_helper"
require "stringio"
require_relative "../../lib/zr/cli"

# The command builds on Ruby 4 and later. It is quiet on the series of the
# pinned ruby (.ruby-version): a build reads the standard library of that
# ruby, and the tests check zr against the output of that ruby.
class CliTest < Minitest::Test
  # A later release of the pinned series, a ruby of the next series, and
  # one older than any ruby that zr runs on.
  def same_series = "#{Zr::RUBY[/\A\d+\.\d+/]}.99"
  def next_series = "#{Zr::RUBY.to_i}.#{Zr::RUBY.split(".")[1].to_i + 1}.0"
  def too_old = "#{Zr::RUBY_MINIMUM.to_i - 1}.4.7"

  def test_pinned_ruby_matches_ruby_version_file
    assert_equal File.read(File.expand_path("../../.ruby-version", __dir__)).strip, Zr::RUBY_PIN
  end

  def test_the_pinned_series_builds_with_no_note
    [Zr::RUBY, same_series].each do |version|
      assert_nil Zr::CLI::Refusals.host_refusal(version)
      assert_nil Zr::CLI::Refusals.host_note(version)
    end
  end

  def test_another_series_builds_with_a_note
    assert_nil Zr::CLI::Refusals.host_refusal(next_series)
    assert_equal "zr #{Zr::VERSION} is tested with ruby #{Zr::RUBY_PIN}; this is ruby #{next_series}",
                 Zr::CLI::Refusals.host_note(next_series)
    assert_output(nil, "zr: warning: #{Zr::CLI::Refusals.host_note(next_series)}\n") { Zr::CLI::Refusals.pinned!(next_series) }
  end

  def test_an_older_ruby_is_refused_with_message
    assert_equal "zr #{Zr::VERSION} runs on ruby #{Zr::RUBY_MINIMUM} or later. " \
                 "Install ruby #{Zr::RUBY_PIN}: #{Zr::DOCS_URL}/how-to/install.md",
                 Zr::CLI::Refusals.host_refusal(too_old)
  end

  def test_a_build_on_an_older_ruby_stops_with_the_refusal_status
    error = assert_raises(SystemExit) do
      assert_output(nil, "zr: #{Zr::CLI::Refusals.host_refusal(too_old)}\n") { Zr::CLI::Refusals.pinned!(too_old) }
    end
    assert_equal Zr::CLI::REFUSED, error.status
    assert_nil Zr::CLI::Refusals.pinned!(Zr::RUBY)
  end
end

# What `zr` prints when it refuses a form of Ruby.
class CliRefusalTest < Minitest::Test
  def test_a_refused_form_shows_the_line_a_caret_and_the_docs
    Dir.mktmpdir("zr-cli-refusal-") do |dir|
      file = File.join(dir, "app.rb")
      File.write(file, "p 1\nBEGIN { p 2 }\n")
      error = Zr::Refused.unsupported("`BEGIN { }` here", file: file, line: 2, column: 1)

      report = Zr::CLI::Refusals.refusal_report(error)

      assert_equal ["zr: #{file}:2:1: zr does not support `BEGIN { }` here yet", "    BEGIN { p 2 }", "    ^",
                    "zr: #{Zr::CLI::Refusals::SUPPORT} lists what zr supports"], report.lines(chomp: true)
    end
  end

  def test_a_message_only_refusal_prints_only_the_message
    assert_equal "zr: a.rb:3: Primitive.x takes keywords", Zr::CLI::Refusals.refusal_report(Zr::Refused.new("a.rb:3: Primitive.x takes keywords"))
  end
end

# How `zr run` ends: as the program ended.
class CliExitTest < Minitest::Test
  # The status of a child that exits with `code`, or that `signal` stops.
  def status_of(code: 0, signal: nil)
    pid = fork do
      if signal
        Zr::CLI::Runner.default_action!(Signal.list.fetch(signal))
        Process.kill(signal, Process.pid)
        sleep 1
      end
      exit!(code)
    end
    Process.wait(pid)
    $?
  end

  def test_run_exits_with_the_program_status
    error = assert_raises(SystemExit) { Zr::CLI::Runner.exit_as(status_of(code: 3)) }
    assert_equal 3, error.status
  end

  def test_a_signal_that_stops_the_program_stops_zr_too
    %w[TERM SEGV].each do |signal|
      status = status_of(signal: signal)
      pid = fork { Zr::CLI::Runner.exit_as(status) }
      Process.wait(pid)

      assert_predicate $?, :signaled?, signal
      assert_equal Signal.list.fetch(signal), $?.termsig, signal
    end
  end
end

# How `zr` reads its command line, and what it says when it cannot.
class CliParseTest < Minitest::Test
  CLI = Zr::CLI
  Options = Zr::CLI::Options

  def test_run_gives_every_word_after_the_file_to_the_program
    opts = Options.parse("run", %w[app.rb -n 5 --x])

    assert_equal "app.rb", opts[:input]
    assert_equal %w[-n 5 --x], opts[:args]
  end

  def test_run_reads_options_before_the_file
    opts = Options.parse("run", %w[--emit wasm --target=wasm32-wasi app.rb a])

    assert_equal "wasm", opts[:emit]
    assert_equal "wasm32-wasi", opts[:triple]
    assert_equal %w[a], opts[:args]
  end

  def test_a_double_dash_before_the_file_ends_the_options
    assert_equal ["-app.rb", ["a"]], Options.parse("run", %w[-- -app.rb a]).values_at(:input, :args)
  end

  def test_build_reads_options_after_the_file
    opts = Options.parse("build", %w[app.rb -o app --emit obj])

    assert_equal ["app.rb", "app", "obj"], opts.values_at(:input, :output, :emit)
  end

  def test_link_collects_each_argument_in_order
    opts = Options.parse("build", %w[app.rb -o app --link a.o --link=-Wl,-x --link -framework --link AppKit])

    assert_equal ["a.o", "-Wl,-x", "-framework", "AppKit"], opts[:link]
  end

  def test_gem_collects_each_name_and_value_in_order
    opts = Options.parse("build", %w[app.rb -o app --gem csv=3.3.6 --gem=rainbow=vendor/rainbow])

    assert_equal [%w[csv 3.3.6], %w[rainbow vendor/rainbow]], opts[:gems]
  end

  def test_gemfile_names_the_lock_to_read
    assert_equal "app/Gemfile", Options.parse("run", %w[--gemfile app/Gemfile app.rb])[:gemfile]
  end

  def test_emit_binary_is_the_default_kind
    assert_nil Options.parse("build", %w[app.rb -o app --emit binary])[:emit]
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
      %w[build app.rb -o] => "zr build: -o needs a path",
      %w[build app.rb -o app --link] => "zr build: --link needs an argument",
      %w[build app.rb -o no/such/dir/app] => "zr build: -o no/such/dir/app: the directory no/such/dir does not exist",
      %w[build app.rb -o app --gem csv] => "zr build: --gem needs <name>=<version> or <name>=<dir>, for example --gem csv=3.3.6"
    }.each do |(command, *args), line|
      _, err = assert_exit(2) { Options.parse(command, args) }
      assert_equal "#{line}\nRun 'zr help #{command}' for usage.\n", err, args.inspect
    end
  end

  # A word that names no command is the script, as for ruby.
  def test_a_word_that_is_no_command_is_a_missing_script
    _, err = assert_exit(1) { CLI.start(%w[frobnicate app.rb]) }

    assert_equal "zr: No such file or directory -- frobnicate (LoadError)\n", err
  end

  # An option is ruby's (lib/zr/cli/ruby_options.rb), and ruby rejects an
  # unknown one with status 1.
  def test_an_unknown_option_or_a_near_command_says_so
    _, err = assert_exit(1) { CLI.start(%w[--frob]) }
    assert_equal "zr: invalid option --frob  (-h will show valid options) (RuntimeError)\n", err

    { "biuld" => "build", "rn" => "run", "doctr" => "doctor", "gemss" => "gems" }.each do |typo, name|
      _, err = assert_exit(2) { CLI.start([typo]) }
      assert_equal "zr: unknown command '#{typo}'; did you mean '#{name}'?\nRun 'zr help' for usage.\n", err
    end
  end

  # Each command prints its help for -h and --help, and nothing else.
  def test_every_command_has_help
    %w[doctor cache version help inspect diff gems].each do |command|
      out, = assert_exit(0) { CLI.start([command, "--help"]) }
      assert_match(/\AUsage: zr #{command}/, out, command)
    end
    _, err = assert_exit(2) { CLI.start(%w[doctor extra]) }
    assert_equal "zr doctor: unexpected argument 'extra'\nRun 'zr help doctor' for usage.\n", err
  end

  def test_machine_and_targets_are_not_commands
    %w[machine targets].each do |word|
      _, err = assert_exit(1) { CLI.start([word]) }
      assert_equal "zr: No such file or directory -- #{word} (LoadError)\n", err
    end
  end

  def test_the_help_of_build_names_each_target
    page = CLI::Help::PAGES.fetch("build").gsub(/\s+/, " ")
    Zr::Target.all.each { |target| assert_includes page, target.triple }
    assert_includes page, "`zr doctor` shows what this host can build"
  end

  def test_an_unknown_target_lists_the_targets
    _, err = assert_exit(2) { Options.target_for("sparc", nil, "build") }
    assert_equal "zr build: unknown target 'sparc'. The targets are aarch64-apple-darwin, aarch64-linux-musl, " \
                 "wasm32-wasi\nRun 'zr help build' for usage.\n", err
  end

  # `-v` prints the description of the ruby that zr matches, as ruby -v
  # does; `--version` names zr.
  def test_version_names_the_ruby_that_zr_matches
    assert_equal "#{Zr.ruby_description(Zr::Target.default.ruby_platform)}\n", capture_io { CLI.start(%w[-v]) }.first
  end

  # With a terminal for standard input. Otherwise zr reads the program
  # from it, as ruby does.
  def test_no_command_prints_the_usage_on_stderr_and_exits_2
    terminal = StringIO.new.tap { |io| io.define_singleton_method(:tty?) { true } }
    stdin = $stdin
    $stdin = terminal
    _, err = assert_exit(2) { CLI.start([]) }

    assert_match(/\AUsage: zr <command>/, err)
  ensure
    $stdin = stdin
  end

  def test_help_for_a_command_prints_its_options_and_exits_0
    out, = assert_exit(0) { CLI.start(%w[build --help]) }

    assert_match(/\AUsage: zr build/, out)
    assert_match(/-o, --output/, out)
    assert_equal CLI::Help::PAGES.fetch("run"), capture_io { CLI.start(%w[help run]) }.first
  end

  # A command's missing input is a usage error. In ruby mode, ruby's own
  # status and message.
  def test_a_missing_file_prints_one_line_and_exits_2
    [%w[run], %w[build -o x], %w[diff], %w[gems], %w[inspect]].each do |command, *options|
      _, err = assert_exit(2) { CLI.start([command, *options, "no_such_file.rb"]) }

      assert_equal "zr: no such file: no_such_file.rb\n", err, command
    end
    _, err = assert_exit(1) { CLI.start(%w[no_such_file.rb]) }
    assert_equal "zr: No such file or directory -- no_such_file.rb (LoadError)\n", err
  end

  # A host that runs no native target (x86_64 Linux) builds a darwin
  # binary by default. `zr build` says so, and `zr run` refuses with a
  # way to run the program there.
  def test_a_host_that_cannot_run_the_default_target_says_what_to_do
    Checks.with_host("x86_64-linux-gnu") do
      target = Zr::Target.default
      _, err = assert_exit(Zr::CLI::REFUSED) { CLI::Refusals.refuse("app.rb", "run", nil, target, chosen: false) }
      assert_equal "zr: app.rb: this computer cannot run aarch64-apple-darwin binaries. zr builds one for macOS on " \
                   "Apple Silicon. To run the program here, use 'zr run --emit wasm app.rb'.\n", err

      _, err = capture_io { CLI::Refusals.refuse("app.rb", "build", nil, target, chosen: false) }
      assert_match(/\Azr: this computer cannot run aarch64-apple-darwin binaries\. .* --emit wasm/, err)
      assert_equal ["", ""], capture_io { CLI::Refusals.refuse("app.rb", "build", nil, target, chosen: true) }
    end
  end

  # An error that escapes a command prints one line, with no backtrace.
  def test_guard_turns_an_error_into_one_line_and_a_status
    _, err = assert_exit(2) { CLI.guard { raise Zr::Config::Invalid, "ZR_JOBS is \"x\"." } }
    assert_equal "zr: ZR_JOBS is \"x\".\n", err

    _, err = assert_exit(1) { CLI.guard { raise Zr::Paths::Missing, "HOME is not set." } }
    assert_equal "zr: HOME is not set.\n", err

    _, err = assert_exit(1) { CLI.guard { raise NoMethodError, "undefined method 'x'" } }
    assert_equal "zr: internal error: NoMethodError: undefined method 'x'. This is a defect in zr. Report it at " \
                 "#{Zr::ISSUES_URL} with the output of 'zr doctor'. Run zr --backtrace (or set ZR_DEBUG=1) to see the backtrace.\n", err

    assert_exit(130) { CLI.guard { raise Interrupt } }
  end

  # The flags of settings come off the front of the words and right after
  # a command's name; the words after them stay for the command.
  def test_settings_come_off_before_and_after_the_command_name
    assert_equal %w[build a.rb -o a --timing], CLI.settings!(%w[--jobs 2 build --no-tune a.rb -o a --timing])
    assert_equal({ "ZR_JOBS" => "2", "ZR_TUNE" => "0" }, Zr::Config.given)
    assert_equal 2, Zr::Config.current.jobs

    assert_equal %w[-e p --timing], CLI.settings!(%w[--timing -e p --timing])
    assert_predicate Zr::Config.current, :timing?

    _, err = assert_exit(2) { CLI.guard { CLI.settings!(%w[-j x run a.rb]) && Zr::Config.current } }
    assert_equal "zr: --jobs is \"x\". Set it to a whole number of 1 or more, for example --jobs=4.\n", err
  ensure
    Zr::Config.given!({})
  end

  def test_guard_shows_the_backtrace_under_zr_debug
    ENV["ZR_DEBUG"] = "1"
    assert_raises(NoMethodError) { CLI.guard { raise NoMethodError, "x" } }
  ensure
    ENV.delete("ZR_DEBUG")
  end

  # A cache that zr cannot write to gives the way to move it.
  def test_an_unwritable_cache_says_how_to_move_it
    error = Errno::EACCES.new(File.join(Zr::Paths.cache, "runtime/x.o"))
    _, err = assert_exit(1) { CLI.guard { raise error } }
    assert_match(/\Azr: Permission denied .* Set XDG_CACHE_HOME \(or ZR_CACHE\) to a directory that you can write to/, err)

    _, err = assert_exit(1) { CLI.guard { raise Errno::EACCES, "/etc/hosts" } }
    assert_equal "zr: Permission denied - /etc/hosts\n", err
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
