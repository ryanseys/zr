# frozen_string_literal: true
# zr-test: eval

require "test_helper"
require "open3"
require "tmpdir"
require_relative "../../lib/zr/cli"

# `zr` with ruby's switches, against ruby with the same words: the same
# output, errors and status. Each case builds a program with no run
# cache, so the file evicts no other test's binaries; a fact that the
# parser alone decides is in ruby_options_test.rb. Where ruby names
# itself, zr names itself.
class RubyModeTest < Minitest::Test
  EXE = File.join(ROOT, "exe/zr")

  # The environment of both: no bundler and no collector limits of the
  # test run, which ruby would load or warn about.
  ENV_OF_BOTH = Zr::ChildRuby::UNBUNDLED.merge(Zr::GcTuning::GC_ENV.transform_values { nil }).freeze

  FILES = {
    "in.txt" => "a b\nc d\n",
    "x.rb" => "p [:x, $VERBOSE, ARGV]\n",
    "sh.rb" => "#!/usr/bin/env ruby -w\np $VERBOSE\n",
    "s.rb" => "p [$x, $foo, $a_b, ARGV]\n",
    "xs.txt" => "garbage\n#!ruby -l\np __LINE__\nputs 'hi'\n",
    "sub/y.rb" => "p Dir.pwd.end_with?('sub')\n",
    "lib/foo.rb" => "module Foo; end\n",
    "bad.rb" => "def x\n  p (\nend\n",
    "handler.rb" => "at_exit { puts 'handler ran' }\n",
    "unparsed.rb" => "x = 1\nif true\n  1 +\n",
    "warns.rb" => "case 1\nwhen 1\nwhen 1\nend\nif (y = 1) then end\nx = 1...\n2\n",
    "warns_bad.rb" => "x = 1...\n2\nfoo(\n",
    "frozen.rb" => "# frozen_string_literal: true\ns = 'abc'\nbegin; s << 'x'; rescue => e; p e.message; end\n" \
                   "t = [\n  'lit']\nbegin; t[0].upcase!; rescue => e; p e.message; end\n",
    "chilled.rb" => "s = 'c'\ns << 'x'\np s\n",
    "detail.rb" => "class SyntaxError\n  def detailed_message(**)\n    Thread.new {}.join\n" \
                   "    \"<\#{super}>\n<\#{File.basename(__FILE__)}>\"\n  end\nend\n",
    "showpath.rb" => "class SyntaxError\n  def detailed_message(**) = \"path=\#{path}\n\#{super}\"\nend\n",
    "hybrid.sh" => "#!/usr/bin/env bash\necho error && exit 1\n#!ruby\nputs 'success'\n",
    "bt.rb" => "def a = raise('oops')\ndef b = a\ndef c = b\ndef d = c\nbegin\n  d\nrescue => e\n  puts e.full_message(highlight: false)\nend\nd\n"
  }.freeze

  def test_e_code_runs_as_the_file_dash_e
    same_as_ruby("-e", "p [$0, __FILE__, __LINE__, __dir__, defined?(DATA)]", "-e", "p ARGV", "--", "-x", "y")
  end

  def test_a_script_and_its_arguments
    same_as_ruby("x.rb", "a", "-b")
    same_as_ruby("--", "x.rb", "q")
  end

  def test_standard_input_is_the_program_without_a_script
    same_as_ruby(stdin: "p [$0, __FILE__, DATA.read]\n__END__\nhi\n")
    same_as_ruby("-", "a", stdin: "p ARGV\n")
  end

  # A program's `RbConfig.ruby` is the zr that ran it, as a ruby
  # program's is its ruby.
  def test_rbconfig_ruby_runs_the_interpreter_that_ran_the_program
    same_as_ruby("-e", 'system(RbConfig.ruby, "-e", "print 6 * 7; exit 7"); p $?.exitstatus')
  end

  def test_the_loop_switches_read_their_input_as_ruby
    same_as_ruby("-lane", "print $F.reverse.join(' ')", "in.txt")
    same_as_ruby("-pe", "$_.upcase!", "in.txt")
    same_as_ruby("-n", "-e", "BEGIN { p :b }; END { p :e }; print if /c/", "in.txt")
    same_as_ruby("-F:", "-ane", "p $F, [$-a, $-l, $-p]", stdin: "a:b\n")
  end

  def test_a_program_that_kills_itself_dies_of_the_signal
    in_dir do |dir|
      _, err, status = Open3.capture3(ENV_OF_BOTH, EXE, "-e", "Process.kill(:KILL, $$); sleep 1", chdir: dir)

      assert_equal ["", Signal.list["KILL"]], [err, status.termsig]
    end
  end

  def test_the_loop_switches_define_chomp_chop_sub_and_gsub_on_the_last_line
    same_as_ruby("-n", "-e", "chomp; chop; sub(/b/, 'X'); gsub(/c/) { 'Y' }; p $_", stdin: "abc1\nbcd2\n")
    same_as_ruby("-n", "-e", "p Kernel.private_method_defined?(:chomp)", stdin: "\n")
    same_as_ruby("-n", "-e", "Kernel.chomp; Kernel.chop; p $_", stdin: "abc\n")
    same_as_ruby("-e", "p Kernel.private_method_defined?(:chomp)")
  end

  def test_parse_warnings_follow_verbose_and_go_through_warning_warn
    same_as_ruby("-W0", "-e", "{a: 1, a: 2}")
    same_as_ruby("-e", "{a: 1, a: 2}")
    same_as_ruby("-w", "-e", "eval(%q(defined?(x); 1))")
    same_as_ruby("-e", "def Warning.warn(m) = print(%q(caught: ), m); eval(%q({b: 1, b: 2}))")
  end

  def test_warning_switches_set_verbose_and_the_categories
    same_as_ruby("-w", "x.rb")
    same_as_ruby("-W0", "-e", "p $VERBOSE; warn 'shown'")
    same_as_ruby("-W:no-deprecated", "-e", "p [Warning[:deprecated], Warning[:experimental], $VERBOSE]")
    same_as_ruby("-w", "-e", "x = 1")
    same_as_ruby("sh.rb")
  end

  def test_include_directories_split_and_expand_as_ruby
    same_as_ruby("-I", "./\u3042:./b:c", "-e", "p $LOAD_PATH.first(3).map { _1.sub(Dir.pwd, %(PWD)) }")
  end

  def test_load_path_and_required_libraries
    same_as_ruby("-Ilib", "-rfoo", "-e", "p Foo, $LOADED_FEATURES.grep(/foo/).size, $LOAD_PATH.include?(File.expand_path('lib'))")
  end

  # -rrubygems is the gem prelude's own load, not a second one that its
  # Gem autoload would start while rubygems.rb loads.
  def test_requiring_rubygems_with_r
    same_as_ruby("-rrubygems", "-e", "p Gem::VERSION.is_a?(String), $LOADED_FEATURES.grep(/rubygems.rb\\z/).size")
    same_as_ruby("-rrubygems", "-e", "p 1")
  end

  def test_s_x_and_c_dir
    same_as_ruby("-s", "s.rb", "-x", "-foo=bar", "-a-b", "z")
    same_as_ruby("-s", "s.rb", "-a.b")
    same_as_ruby("-x", "xs.txt")
    same_as_ruby("-x", "in.txt")
    same_as_ruby("-C", "sub", "y.rb")
  end

  # rubygems loads monitor.rb as ruby starts; without gems, the program
  # loads it itself.
  def test_monitor_rb_loads_with_rubygems
    same_as_ruby("-e", "p defined?(MonitorMixin), require('monitor')")
    same_as_ruby("--disable-gems", "-e", "p defined?(MonitorMixin), require('monitor'), defined?(MonitorMixin)")
  end

  def test_separators_and_encodings
    same_as_ruby("-l", "-00", "-e", "p [$/, $\\]")
    same_as_ruby("-E", "ISO-8859-1:UTF-8", "-e", "p [Encoding.default_external, Encoding.default_internal]")
    same_as_ruby("--disable-gems", "--enable=frozen-string-literal", "-e", "p defined?(Gem), 'a'.frozen?")
    same_as_ruby("-072", "-e", "p $/, $/.frozen?, $-0.frozen?")
    same_as_ruby("-Ke", "-e", "p [__ENCODING__, Encoding.default_external, Encoding.default_internal]")
    same_as_ruby("-U", "-KS", "-e", "p [__ENCODING__, Encoding.default_internal]")
    same_as_ruby("-U", "-E:ascii", "-e", "1")
    same_as_ruby("-wKe", "-e", "p __ENCODING__.name")
    same_as_ruby("-W0", "-e", "p $-W")
    same_as_ruby("-W1", "-e", "p $-W")
    same_as_ruby("-W", "-e", "p $-W")
    same_as_ruby("-e", "p $-W, defined?($-W)")
    # An internal encoding that a switch sets gives the standard streams
    # the default encodings, and a write converts to the external one.
    streams = "p [$stdin, $stdout, $stderr].map { [_1.external_encoding, _1.internal_encoding] }"
    ["-E:utf-8", "-Eeuc-jp:utf-8", "-U", "-Eutf-8"].each { |switch| same_as_ruby(switch, "-e", streams) }
    same_as_ruby("-Eutf-8:cp932", "-e",
                 'puts "\x82\xa0".dup.force_encoding("cp932"); $stderr = $stdout; raise "\x82\xa0".dup.force_encoding("cp932")')
    same_as_ruby("-e", "Encoding.default_internal = 'utf-8'; #{streams}")
    same_as_ruby("-w", "-e", "Encoding.default_internal = 'EUC-JP'; p Encoding.default_internal")
  end

  def test_a_launcher_script_and_the_backtrace_limit
    same_as_ruby("hybrid.sh")
    same_as_ruby("--backtrace-limit=1", "bt.rb")
    same_as_ruby("--disable=did_you_mean", "--backtrace-limit=0", "-e", "p defined?(DidYouMean), Thread::Backtrace.limit")
  end

  def test_syntax_check_and_syntax_errors
    same_as_ruby("-c", "-e", "p 1")
    same_as_ruby("-c", "bad.rb")
    same_as_ruby("-e", "p (")
    # The -r libraries load before the report, and their exit handlers run.
    same_as_ruby("-r./handler.rb", "-e", "{")
    # The report goes through SyntaxError#detailed_message, which a library
    # may redefine, and the error has the script's path.
    same_as_ruby("-r./detail.rb", "unparsed.rb")
    same_as_ruby("-r./showpath.rb", "unparsed.rb")
    same_as_ruby("-r./detail.rb", "-", stdin: "1+\n")
    # The parse warns at the program's level, before the report.
    same_as_ruby("-w", "unparsed.rb")
    same_as_ruby("-W0", "unparsed.rb")
    same_as_ruby("--disable-gems", "unparsed.rb")
  end

  # A program with no file warns as it parses too: -e, and a script on
  # standard input.
  def test_a_program_with_no_file_prints_its_parse_warnings_before_the_report
    same_as_ruby("-w", "-e", "p 1 if 1; p(")
    same_as_ruby("-e", "p :a=>1, :a=>2; p(")
    same_as_ruby("-W0", "-e", "p :a=>1, :a=>2; p(")
    same_as_ruby("-w", "-", stdin: "p 1 if 1; p(\n")
  end

  # -c prints the parse's warnings at the program's level, before "Syntax
  # OK" or the report of a program that does not parse
  # (test_syntax.rb test_duplicated_when_check_option).
  def test_syntax_check_prints_the_parse_warnings
    same_as_ruby("-wc", "warns.rb")
    same_as_ruby("-c", "warns.rb")
    same_as_ruby("-W0", "-c", "warns.rb")
    same_as_ruby("-wc", "-", stdin: "case 1\nwhen 1\nwhen 1\nend\n")
    same_as_ruby("-wc", "warns_bad.rb")
    same_as_ruby("-c", "warns_bad.rb")
  end

  # -y and --dump print in place of the run; prism's tree prints as ruby's
  # C printer prints it.
  def test_dump_prints_the_syntax_check_and_the_tree
    same_as_ruby("-y", "-e", "p 1")
    same_as_ruby("--dump=syntax,parsetree", "x.rb")
    same_as_ruby("--disable-gems", "--dump=parsetree", "-e", "%I[foo bar]")
    same_as_ruby("--dump", "p", "-e", "def m(a, *b, k: 1, **o, &blk) = yield\nm(1) { |q| \"\\x01\#{q}\" }; x = -2**64; 1e400")
    same_as_ruby("--dump=parsetree", "bad.rb")
    same_as_ruby("--dump=syntax", "missing.rb")
    same_as_ruby("--dump=foo,-bar,syntax+baz", "-e", "p 1")
    same_as_ruby("--dump=foo", "x.rb")
    same_as_ruby("--dump=copyright,syntax", "-e", "p 1")
  end

  # --debug=frozen-string-literal: a literal keeps where it was made, which
  # a FrozenError and the chilled String's warning name.
  def test_debug_frozen_string_literal_names_where_a_string_was_made
    same_as_ruby("--debug=frozen-string-literal", "frozen.rb")
    same_as_ruby("--debug-frozen-string-literal", "frozen.rb")
    same_as_ruby("frozen.rb")
    same_as_ruby("-W:deprecated", "--debug=frozen-string-literal", "chilled.rb")
    same_as_ruby("-W:deprecated", "chilled.rb")
    same_as_ruby("--debug=frozen-string-literal", "-e", "p $DEBUG")
    # -d and --debug turn every debug feature on, this one too.
    same_as_ruby("--disable-gems", "-d", "frozen.rb")
    same_as_ruby("--disable-gems", "--debug", "frozen.rb")
    same_as_ruby("--disable-gems", "--enable-frozen-string-literal", "--debug", "-e", "'foo' << 'bar'")
  end

  # -S looks in RUBYPATH, then PATH, as dln_find_1 does: "~" is HOME, an
  # empty entry is the current directory, and a path too long for the
  # buffer is skipped, with a warning under -w.
  def test_s_searches_rubypath_then_path
    same_as_ruby("-S", "x.rb", env: { "RUBYPATH" => "~", "HOME" => "DIR" })
    same_as_ruby("-S", "y.rb", env: { "RUBYPATH" => "/nope:~/sub", "HOME" => "DIR" })
    same_as_ruby("-S", "x.rb", env: { "RUBYPATH" => ":/nope" })
    same_as_ruby("-S", "sub/y.rb", env: { "RUBYPATH" => "DIR" })
    same_as_ruby("-S", "-w", "nothing_here", env: { "RUBYPATH" => "~", "HOME" => "/foo" * 1024 })
    same_as_ruby("-S", "-w", "nothing_here", env: { "RUBYPATH" => "~#{"/foo" * 1024}", "HOME" => "/foo" })
    same_as_ruby("-S", "nothing_here", env: { "RUBYPATH" => "~", "HOME" => "/foo" * 1024 })
  end

  # A long backtrace limit runs (ruby_options_test.rb checks its bounds).
  def test_a_long_backtrace_limit_runs
    same_as_ruby("--backtrace-limit=4611686018427387904", "-e", "p Thread::Backtrace.limit; raise 'x'")
  end

  # A shebang line that ends with "\r\n" warns, once, unless -W0.
  def test_a_shebang_line_with_a_carriage_return_warns
    same_as_ruby(stdin: "#!ruby -KU -Eutf-8\r\np \"あ\"\r\n")
    same_as_ruby("-W0", stdin: "#!ruby\r\np 1\r\n")
    same_as_ruby("-w", stdin: "#!ruby\r\np 1\r\n")
    same_as_ruby("-x", stdin: "junk\n#!ruby -w\r\np 2\r\n")
  end

  # A first line of `#!` alone is a comment; with anything after it that
  # does not name ruby, it is a launcher, and the script runs from the
  # first `#!ruby` line (test_rubyoptions.rb's test_shebang).
  def test_a_bare_shebang_line_is_a_comment
    same_as_ruby(stdin: "#!")
    same_as_ruby("-c", stdin: "#!")
    same_as_ruby(stdin: "#!\np 1\n")
    same_as_ruby(stdin: "#! \np 1\n")
    same_as_ruby(stdin: "#!\r\np 1\n")
  end

  # Without gems, the libraries of ruby's gem prelude are not there.
  def test_no_gems_means_no_gem_prelude_libraries
    code = "p [defined?(ErrorHighlight), defined?(SyntaxSuggest), defined?(DidYouMean), defined?(Gem)]; foo rescue p $!.message"
    same_as_ruby("--disable=gems", "-e", code)
    same_as_ruby("--disable-did_you_mean", "-e", code)
    same_as_ruby("--disable-error_highlight", "-e", code)
    same_as_ruby("--disable=syntax_suggest", "-e", code)
    same_as_ruby("--disable=gems", "-e", "nil.foo")
    # The first error display loads only the libraries that are still on.
    same_as_ruby("--disable=error_highlight", "-e", "[1].frist")
    same_as_ruby("--disable=did_you_mean", "-e", "[1].frist")
  end

  # ruby 4.1 makes the libraries autoloads; the first error display loads them.
  def test_the_message_decorators_load_at_the_first_error_display
    same_as_ruby("-e", "p Object.autoload?(:DidYouMean); [1].frist rescue p $!.detailed_message; p Object.autoload?(:DidYouMean)")
    same_as_ruby("-e", "[1].frist")
  end

  def test_errors_before_the_program_runs
    same_as_ruby("nope.rb")
    same_as_ruby("no/such/script")
    same_as_ruby("", "a", stdin: "p ARGV, $0")
    # A first line that runs another interpreter makes the script run as
    # with -x, from standard input too.
    same_as_ruby(stdin: "#! /bin/not_the_interpreter\r\np 1\r\n")
    same_as_ruby(stdin: "#! /bin/not_the_interpreter\np 1\n#!ruby\np 2\n")
    same_as_ruby("--disable-gems", "-e", "begin; require 'no_such_feature_zr'; rescue LoadError => e; p e.message; end")
    # The platform is the build host's, which zr's target need not match.
    same_as_ruby("-v", "-e", "p 1", platform: true)
    same_as_ruby("-q")
    same_as_ruby("-C", "nodir", "-e", "1")
    same_as_ruby("-e", "exit 7")
  end

  def test_in_place_editing_writes_each_file_and_keeps_a_backup
    in_dir do |dir|
      File.write(File.join(dir, "f.txt"), "a\nb\n")
      out, err, status = Open3.capture3(ENV_OF_BOTH, EXE, "-i.bak", "-pe", "$_.upcase!", "f.txt", chdir: dir)

      assert_equal ["", "", 0], [out, err, status.exitstatus]
      assert_equal ["A\nB\n", "a\nb\n"], %w[f.txt f.txt.bak].map { |name| File.read(File.join(dir, name)) }
    end
  end

  private

  # Runs `argv` under ruby and under zr in a directory with FILES, and
  # checks that both give the same output, errors and status.
  #: (*String argv, ?stdin: String) -> void
  # `env` is more of the environment, where "DIR" stands for the
  # directory that both run in. `platform` masks the " [platform]" that
  # ends a line of the output, as in RUBY_DESCRIPTION.
  def same_as_ruby(*argv, stdin: "", env: {}, platform: false)
    in_dir do |dir|
      given = ENV_OF_BOTH.merge(env.transform_values { |value| value.gsub("DIR", dir) })
      ruby = Open3.capture3(given, RbConfig.ruby, *argv, stdin_data: stdin, chdir: dir)
      zr = Open3.capture3(given, EXE, "--no-run-cache", *argv, stdin_data: stdin, chdir: dir)
      expected = [ruby[0], ruby[1].gsub(/^#{Regexp.escape(RbConfig.ruby)}:|^ruby:/, "zr:"), ruby[2].exitstatus]
      actual = [zr[0], zr[1], zr[2].exitstatus]
      expected[0], actual[0] = [expected[0], actual[0]].map { |out| out.sub(/ \[[\w.-]+\]$/, " [platform]") } if platform

      assert_equal expected, actual, argv.inspect
    end
  end

  #: () { (String) -> void } -> void
  def in_dir
    Dir.mktmpdir("zr-ruby-mode-") do |dir|
      dir = File.realpath(dir)
      FILES.each do |name, text|
        path = File.join(dir, name)
        FileUtils.mkdir_p(File.dirname(path))
        File.write(path, text)
      end
      yield dir
    end
  end
end
