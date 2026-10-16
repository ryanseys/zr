# Labels are fstrings in ruby's encodings: a method's name and
# "<compiled>" in US-ASCII, a formatted label in ASCII-8BIT. `of` takes
# an iseq and a backtrace location too. `to_a` lists the parameters as
# the local table holds them (the labels of the optionals' code aside),
# and whether a method uses its block.
# rubocop:disable Lint/UnusedMethodArgument, Lint/UselessMethodDefinition, Naming/PredicateMethod, Lint/NestedMethodDefinition
ISeq = RubyVM::InstructionSequence

c = Class.new { def foobar = proc { 1 } }
label = ISeq.of(c.instance_method(:foobar)).label
p [label.encoding, label.frozen?, label.equal?(eval("# encoding: us-ascii\n'foobar'.freeze"))]
p [ISeq.of(c.new.foobar).label, ISeq.of(c.new.foobar).label.encoding, ISeq.compile("1").label.encoding]
walk = ->(iseq) { [[iseq.label, iseq.label.encoding.to_s, iseq.base_label], *[].tap { |kids| iseq.each_child { |child| kids << walk.(child) } }] }
p walk.(ISeq.compile("class C; def m; begin; rescue; 1; ensure; 2; end; 1.times { }; end; end; def é; end"))

iseq = ISeq.compile("p 1", __FILE__)
p [ISeq.of(iseq).equal?(iseq), ISeq.of(proc {}).path == __FILE__, ISeq.of(method(:p)), ISeq.of("x".method(:upcase))]
location = begin
  raise "x"
rescue => e
  e.backtrace_locations[0]
end
p [ISeq.of(location).path == __FILE__, ISeq.of(location).label]

def m1(a, *c, d, e:, f: 2, **g, &h) = yield
def m2(a, b) = super
def m3(*) = super
def m4 = binding
def m5 = block_given?
def m6(...) = m1(...)
def m7 = proc { yield }
def m8(a, ...) = 1
def m9(**nil) = 1
def m10(f: "s", g: :y, h: [], i: nil, j: 1.5, k: 2r, l: -1, m: true) = 1
def m11(**) = 1
def m12(&) = 1
def m13 = super(1)
def m14 = [1].each { _1 + yield }
def m15 = def inner = yield
(1..15).each { |i| p [i, ISeq.of(method(:"m#{i}")).to_a[11]] }
blocks = [proc { |a| }, proc { |a, | }, proc { |(a, b)| }, proc { _1 }, proc { _2 }, proc { it }, lambda { |a| }]
blocks += [proc { |a, *c, &d| }, proc { |a, b| }]
blocks.each do |block|
  p ISeq.of(block).to_a[11]
end
# rubocop:enable Lint/UnusedMethodArgument, Lint/UselessMethodDefinition, Naming/PredicateMethod, Lint/NestedMethodDefinition
