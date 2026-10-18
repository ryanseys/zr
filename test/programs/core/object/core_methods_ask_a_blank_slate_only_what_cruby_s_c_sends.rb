# A blank slate undefines every method but __id__ and __send__, as rbs's
# test doubles do (RBS::UnitTest::Convertibles), so any send that CRuby's
# C does not make raises here.
class Blank < BasicObject
  instance_methods.each { |im| undef_method im unless im == :__id__ || im == :__send__ }
end
class ToStr < Blank
  def initialize(v) = @v = v
  def to_str = @v
end
class ToInt < Blank
  def initialize(v) = @v = v
  def to_int = @v
end
class ToF < Blank
  def initialize(v) = @v = v
  def to_f = @v
end
class ToS < Blank
  def initialize(v) = @v = v
  def to_s = @v
end
class ToPath < Blank
  def initialize(v) = @v = v
  def to_path = @v
end
class ToIO < Blank
  def initialize(v) = @v = v
  def to_io = @v
end
class Span < Blank
  def initialize(b, e, x = false) = (@b = b; @e = e; @x = x)
  def begin = @b
  def end = @e
  def exclude_end? = @x
end

def t(label)
  r = yield
  puts "#{label}: #{r.inspect}"
rescue ::Exception => e
  puts "#{label}: !#{e.class}: #{e.message[0, 100]}"
end

# CRuby's C compares VALUEs where the core compares by identity
# (rb_obj_equal, `exc == argv[0]`, `status == Qtrue`), tests truth with
# RTEST, and asks rb_respond_to, which finds the method itself on an
# object that defines no respond_to?.
t("array ==") { [1] == Blank.new }
t("hash ==") { {} == Blank.new }
t("string ==") { "a" == Blank.new }
t("string ===") { "a" === Blank.new }
t("string == to_str") { s = ToStr.new("a"); def s.==(o) = o == "a"; "a" == s }
t("exception same") { e = RuntimeError.new("a"); e.exception(e).equal?(e) }
t("exception message") { RuntimeError.new("a").exception(ToStr.new("b")).message }
t("message to_s") { RuntimeError.new(ToS.new("q")).message }
t("message to_str") { RuntimeError.new(ToStr.new("q")).message }
t("message to_str bad") { o = Object.new; def o.to_str = 1; RuntimeError.new(o).message }
t("exit status") { begin; exit(ToInt.new(3)); rescue SystemExit => e; e.status; end }
t("exit true") { begin; exit(true); rescue SystemExit => e; e.status; end }
t("system exit") { [SystemExit.new(ToStr.new("x")).message, SystemExit.new(true, ToStr.new("y")).message, SystemExit.new(ToStr.new("z")).status] }
t("exit! in a child") { pid = fork { exit!(ToInt.new(4)) }; Process.wait(pid); $?.exitstatus }
t("marshal freeze") { Marshal.load(Marshal.dump("a"), freeze: Blank.new).frozen? }
t("marshal proc freeze") { Marshal.load(Marshal.dump("a"), nil, freeze: Blank.new).frozen? }
t("respond_to? to_str") { 1.respond_to?(ToStr.new("to_s")) }
t("respond_to? blank") { 1.respond_to?(Blank.new) }
t("hash assoc asks the key") { k = Blank.new; def k.==(r) = r == :a; [{a: 1}.assoc(k), {b: 1}.assoc(k)] }
t("hash assoc order") { k = Object.new; def k.==(o) = (puts("k == #{o.inspect}"); false); {a: 1}.assoc(k) }
t("hash assoc float") { {1 => 2}.assoc(1.0) }
t("not tilde") { o = Object.new; def o.=~(x) = Blank.new; o !~ 1 }
t("sample") { r = Blank.new; def r.rand(m) = 0; [1, 2, 3].sample(random: r) }
t("sample n") { r = Blank.new; def r.rand(m) = ToInt.new(0); [1, 2, 3].sample(2, random: r) }
t("shuffle") { r = Blank.new; def r.rand(m) = 0; [1, 2, 3].shuffle(random: r) }
t("shuffle!") { r = Blank.new; def r.rand(m) = 0; [1, 2, 3].shuffle!(random: r) }
t("raise to_str") { begin; raise ToStr.new("m"); rescue => e; [e.class, e.message]; end }
t("raise to_str bad") { o = Object.new; def o.to_str = 1; raise o }
t("raise to_str and exception") { o = Object.new; def o.to_str = "s"; def o.exception(*) = ArgumentError.new("e"); begin; raise o; rescue => e; [e.class, e.message]; end }
t("raise blank exception") { x = Blank.new; def x.exception(m = nil) = ArgumentError.new(m.to_s); begin; raise x, ToS.new("z"); rescue => e; [e.class, e.message]; end }
t("raise respond_to_missing") { o = Object.new; def o.respond_to_missing?(m, p) = m == :exception; def o.method_missing(m, *a) = (m == :exception ? IOError.new("mm") : super); begin; raise o; rescue => e; [e.class, e.message]; end }
t("raise blank") { raise Blank.new }
