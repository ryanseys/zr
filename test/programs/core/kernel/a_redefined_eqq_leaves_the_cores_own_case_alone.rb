# A program that redefines === on nil, true, false, Float, Symbol, String
# or Integer changes no core method: ruby's C tests types without ===.
%w[NilClass TrueClass FalseClass Float Symbol String Integer].each do |k|
  Object.const_get(k).class_eval do
    undef ===
    def ===(*args) = args[0]
  end
end
checks = {
  inspect: -> { [1, nil, :a, "s", 1.5, true].inspect },
  hash: -> { { a: nil, "b" => 1.0 }.to_s },
  format: -> { format("%s %d %.1f", nil, 1, 2.5) },
  interp: -> { "#{nil}#{:a}#{1.5}" },
  integer: -> { Integer("12") + Float("1.5") },
  struct: -> { Struct.new(:a).new(nil).to_a },
  sort: -> { [3, 1, 2].sort.max },
  case_in: -> { 5 in Integer },
  exception: -> { (raise "x" rescue $!.message) },
  string_ops: -> { "a,b".split(",").map(&:upcase).join("-") },
  array_new: -> { Array.new(2) { nil } },
  object_new: -> { Object.new.class },
  kernel: -> { [Array(nil), String(1), Rational(1, 2)] },
}
checks.each do |name, check|
  p [name, check.call]
rescue Exception => e
  p [name, e.class, e.message[0, 80]]
end
# The program's own case sees its ===.
p(case nil when 5 then :five end)
p(case 5 when nil then :nil_eqq end)
