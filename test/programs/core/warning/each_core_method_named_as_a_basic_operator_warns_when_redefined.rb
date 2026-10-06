# Under Warning[:performance], redefining a core method warns when its
# name is one of the basic operators and its class is one that the
# interpreter optimizes: Array#- and String#% too, not only the
# operators that run inline.
Warning[:performance] = true
CLASSES = [Integer, Float, String, Array, Hash, Symbol, Regexp, NilClass, TrueClass, FalseClass, Proc, Range, Object].freeze
NAMES = %i[+ - * / % == === < <= > >= << >> [] []= length size empty? succ =~ freeze -@
           max min hash call & | nil? <=> default pack include? first upcase].freeze

def warned?(klass, name)
  r, w = IO.pipe
  pid = fork do
    r.close
    $stderr.reopen(w)
    begin
      klass.class_eval do
        undef_method name
        define_method(name) { nil }
      end
    rescue NameError
      nil
    end
    exit!(0)
  end
  w.close
  Process.wait(pid)
  text = r.read
  r.close
  text
end

CLASSES.each do |klass|
  warned = NAMES.filter_map do |name|
    text = warned?(klass, name)
    name if text.include?("Redefining '#{klass}##{name}' disables interpreter and JIT optimizations")
  end
  puts "#{klass}: #{warned.join(' ')}"
end
