def t(l)
  r = yield
  puts "#{l}: #{r.inspect}"
rescue Exception => e
  puts "#{l}: !#{e.class}: #{e.message[0, 200]}"
end

require "strscan"
t(:strscan) { s = StringScanner.new("3 apples"); [s.scan(/\d/), s.scan(/\s+/), s.check(/\w+/), s.pos, s.rest, s.matched, s.scan_until(/le/), s.pre_match, s.eos?, s.scan_integer] }
t(:strscan_int) { s = StringScanner.new("0x1f rest"); [s.scan_integer(base: 16), s.rest] }
require "optparse"
t(:optparse) { o = {}; op = OptionParser.new { |x| x.on("-v", "--verbose") { o[:v] = true }; x.on("-nNAME", Integer) { o[:n] = _1 } }; rest = op.parse(%w[-v -n3 file]); [o, rest, op.help.lines.size] }
t(:optparse_err) { OptionParser.new.parse(%w[--nope]) }
require "logger"
t(:logger) { require "stringio"; io = StringIO.new; l = Logger.new(io, formatter: proc { |s, _, p, m| "#{s}:#{p}:#{m}\n" }, progname: "P"); l.info("hi"); l.debug("d"); l.level = :warn; l.info("no"); io.string }
require "pp"
t(:pp) { require "stringio"; o = StringIO.new; PP.pp({a: [1] * 30, b: "x" * 40, c: {d: Struct.new(:e).new(1)}}, o, 40); o.string }
t(:pp_obj) { c = Class.new { def initialize = (@a = 1; @b = [2] * 20) }; Object.const_set(:PPO, c); PP.pp(PPO.new, +"", 30).sub(/0x\h+/, "X") }
require "delegate"
t(:delegate) { d = SimpleDelegator.new([1, 2]); [d.size, d.__getobj__, d.is_a?(Array), DelegateClass(Array).instance_method(:size).owner.class] }
require "forwardable"
t(:forwardable) { c = Class.new { extend Forwardable; def_delegators :@a, :size, :first; def initialize = @a = [7, 8] }; [c.new.size, c.new.first] }
require "singleton"
t(:singleton) { c = Class.new { include Singleton }; [c.instance.equal?(c.instance), (c.new rescue $!.class)] }
require "ostruct"
t(:ostruct) { o = OpenStruct.new(a: 1); o.b = 2; [o.to_h, o.respond_to?(:a), o, o.dig(:a)] }
require "set"
t(:set) { s = Set[3, 1, 2]; [s.sort, s | Set[4], s & Set[1], s ^ Set[1, 9], s.subset?(Set[1, 2, 3, 4]), s.classify(&:odd?), s.to_a, Set[[1, 2]].flatten, s.group_by(&:odd?), (SortedSet rescue $!.class)] }
require "tsort"
t(:tsort) { h = {1 => [2, 3], 2 => [3], 3 => [], 4 => []}; e = ->(&b) { h.each_key(&b) }; c = ->(n, &b) { h[n].each(&b) }; TSort.tsort(e, c) }
require "find"
t(:find) { Dir.mkdir("fz") rescue nil; File.write("fz/a", ""); Find.find("fz").to_a.sort }
require "shellwords"
t(:shellwords) { ["a 'b c' d\\ e".shellsplit, Shellwords.escape("it's"), %w[a b\ c].shelljoin] }
require "benchmark"
t(:benchmark) { Benchmark.realtime { }.class }
require "English"
t(:english) { "ab" =~ /b/; [$PREMATCH, $PID.class, $ERROR_INFO] }
require "pstore"
t(:pstore) { s = PStore.new("ps.db"); s.transaction { s[:a] = 1 }; s.transaction(true) { s[:a] } }
require "yaml/store"
t(:yamlstore) { s = YAML::Store.new("ys.yml"); s.transaction { s[:a] = [1] }; File.read("ys.yml") }
require "weakref"
t(:weakref) { r = WeakRef.new("x" * 3); [r.weakref_alive?, r.size] }
require "getoptlong"
t(:getoptlong) { ARGV.replace(%w[--a 1 x]); g = GetoptLong.new(["--a", GetoptLong::REQUIRED_ARGUMENT]); r = []; g.each { |k, v| r << [k, v] }; [r, ARGV] }
require "bigdecimal"
t(:bigdecimal) { require "bigdecimal/util"; [BigDecimal("0.1") + BigDecimal("0.2"), (BigDecimal("1") / 3).round(20).to_s, BigDecimal("1.23456789").round(3).to_f, "3.14".to_d.class, BigDecimal("NaN").nan?, BigDecimal("123.45").to_s("F"), BigDecimal("2").sqrt(20).to_s[0, 12], BigDecimal::VERSION] }
require "matrix"
t(:matrix) { m = Matrix[[1, 2], [3, 4]]; [m.det, m.inverse, m * m, m.transpose, Vector[1, 2].inner_product(Vector[3, 4])] }
require "prime"
t(:prime) { [Prime.first(5), 97.prime?, 360.prime_division, Prime.each(20).to_a.last] }
t(:did_you_mean) { [DidYouMean::SpellChecker.new(dictionary: %w[apple maple]).correct("appel"), DidYouMean::VERSION.class] }
t(:unicode_norm) { "Å".unicode_normalize(:nfd).length }
t(:abbrev) { require "abbrev"; %w[car cone].abbrev }
t(:observer) { require "observer"; c = Class.new { include Observable }; o = c.new; r = []; w = Object.new; w.define_singleton_method(:update) { |x| r << x }; o.add_observer(w); o.changed; o.notify_observers(5); r }
t(:racc) { require "racc/parser"; Racc::Parser.class }
t(:ripper) { require "ripper"; [Ripper.sexp("a = 1"), Ripper.lex("x+1").map { _1[1] }, Ripper.tokenize("def f; end")] }
t(:ripper_err) { require "ripper"; Ripper.sexp("def (") }
t(:prism) { require "prism"; r = Prism.parse("foo(1)"); [r.value.class, r.errors.size, Prism::VERSION, Prism.lex("1").value.size] }
t(:prism_dump) { require "prism"; Prism.parse("a + 1").value.statements.body[0].inspect.lines.size }
t(:nkf) { require "nkf"; [NKF.nkf("-w", "\xA4\xA2".b.force_encoding("EUC-JP")), NKF.guess("abc")] }
t(:syslog) { require "syslog"; Syslog.respond_to?(:open) }
t(:fiddle) { require "fiddle"; f = Fiddle::Function.new(Fiddle.dlopen(nil)["strlen"], [Fiddle::TYPE_VOIDP], Fiddle::TYPE_SIZE_T); f.call("hello") }
t(:fiddle_import) { require "fiddle/import"; m = Module.new { extend Fiddle::Importer; dlload Fiddle::Handle::DEFAULT; extern "int abs(int)" }; m.abs(-3) }
t(:io_console) { require "io/console"; [IO.respond_to?(:console), (STDIN.winsize rescue $!.class), IO.console_size] }
t(:reline) { require "reline"; Reline.respond_to?(:readline) }
t(:readline) { require "readline"; Readline.class }
t(:irb) { require "irb"; IRB.respond_to?(:start) }
t(:debug_lib) { require "debug/session" rescue $!.class }
t(:power_assert) { require "power_assert"; PowerAssert.respond_to?(:start) }
t(:minitest) { require "minitest"; Minitest::VERSION }
t(:test_unit) { require "test/unit"; Test::Unit::AutoRunner.need_auto_run = false; :ok }
t(:rake) { require "rake"; Rake::VERSION }
t(:bundler) { require "bundler"; Bundler::VERSION }
t(:rubygems) { [Gem::Version.new("1.2.3") <=> Gem::Version.new("1.10"), Gem::Requirement.new("~> 1.2").satisfied_by?(Gem::Version.new("1.9")), Gem.ruby_version.class, Gem::Platform.local.os] }
t(:net_smtp) { require "net/smtp"; Net::SMTP.new("localhost").class }
t(:net_imap) { require "net/imap"; Net::IMAP.class }
t(:rss) { require "rss"; RSS::Parser.parse("<rss version='2.0'><channel><title>t</title><link>l</link><description>d</description></channel></rss>", false).channel.title }
t(:drb) { require "drb/drb"; DRb.start_service("druby://127.0.0.1:0", [1, 2]); u = DRb.uri; r = DRbObject.new_with_uri(u).size; DRb.stop_service; r }
t(:mutex_m) { require "mutex_m"; o = Object.new.extend(Mutex_m); o.synchronize { 1 } }
t(:cgi) { require "cgi/escape"; [CGI.escapeHTML("<&>"), CGI.escape("a b"), CGI.unescape("a+b")] }
t(:win32ole) { require "win32ole" }
t(:open_uri) { require "open-uri"; URI.open("nope-file-zz") }
t(:un) { require "un"; respond_to?(:cp, true) }
t(:expect) { require "expect"; IO.instance_method(:expect).class }
t(:objspace_dump_all) { require "objspace"; ObjectSpace.dump_all(output: :string).lines.size > 10 }
t(:error_highlight) { ErrorHighlight.spot(RuntimeError.new).class rescue $!.class }
t(:syntax_suggest) { require "syntax_suggest"; SyntaxSuggest.respond_to?(:handle_error) }
