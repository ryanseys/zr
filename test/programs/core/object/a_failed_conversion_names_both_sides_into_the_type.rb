# ruby 4.1 writes every failed conversion one way: "no implicit
# conversion of X into T", "can't convert X into T", and "can't convert
# X into T (X#m gives Y)". nil, true and false show by name, any other
# value by its class.
def show
  yield
rescue TypeError => e
  puts e.message
end

class Gives
  def initialize(value) = @value = value
  %i[to_str to_ary to_hash to_int to_a to_s to_i to_f to_r to_io to_regexp to_sym to_proc].each do |name|
    define_method(name) { @value }
  end
end

# Implicit conversions that the object refuses.
show { "a" + nil }
show { "a" + true }
show { "a" + 1 }
show { [1].first(nil) }
show { [1].first("2") }
show { [1].first(false) }
show { [1, 2].fetch(nil) }
show { "abc".match(/b/).begin(nil) }
show { [1] + nil }
show { {}.merge(nil) }
show { Integer.sqrt(nil) }
show { Math.sqrt(nil) }
show { Math.sqrt("4") }
show { Math.sqrt(true) }
show { 1.0 + nil }
show { [1.0].pack("d").unpack1("d") + nil }
show { sleep("1") }
show { File.open(__FILE__) { |io| io.lineno = nil } }
show { (..1).step(1).to_a }

# Explicit conversions that the object has no method for.
show { Integer(nil) }
show { Float(nil) }
show { Float(true) }
show { Float(Object.new) }
show { Rational(nil) }
show { Complex(nil) }
show { Hash(1) }
show { Array(BasicObject.new) rescue puts "BasicObject has no respond_to?" }

# A conversion method that gives the wrong type.
show { "a" + Gives.new(1) }
show { "a" + Gives.new(nil) }
show { [1] + Gives.new("x") }
show { {}.merge(Gives.new(true)) }
show { [1].first(Gives.new("1")) }
show { Array(Gives.new(1)) }
show { Integer(Gives.new("1")) }
show { Float(Gives.new(1)) }
show { Rational(Gives.new([1])) }
show { String.try_convert(Gives.new(:a)) }
show { Array.try_convert(Gives.new(false)) }
show { Hash.try_convert(Gives.new(1)) }
show { Regexp.try_convert(Gives.new("a")) }
show { IO.try_convert(Gives.new("io")) }
show { [1].each(&Gives.new(1)) }
show { "#{Gives.new(1)}" == "1" ? nil : puts("to_s fell back") }
show { File.utime(nil, Gives.new(1), __FILE__) }
