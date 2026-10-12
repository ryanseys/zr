# frozen_string_literal: true

# The lines of this file are templates of Ruby source: long, and with the
# quotes of the source in their %w lists.
# rubocop:disable Layout/LineLength, Lint/PercentStringArray

module Zr
  module Dev
    module Fuzz
      module Gen
        # The feature packs of the writer (Swarm::PACKS). A pack can write
        # top-level definitions once (`setup_<pack>`) and statements for
        # the units (`<pack>_statement`). A program has only the packs that
        # its swarm turned on, each with its own weight.
        module Packs
          # The packs whose statements come from `<pack>_statement`.
          STATEMENT_PACKS = %w[methods blocks objects exceptions pattern meta eval fiber_thread collections strings numeric stdlib
                               gc_pressure explore].freeze

          def setup_packs
            %w[methods objects exceptions meta stdlib].each { |pack| send(:"setup_#{pack}") if swarm.on?(pack) }
          end

          def pack_statements(d)
            STATEMENT_PACKS.filter_map do |pack|
              next unless swarm.on?(pack)

              [swarm.weights.fetch(pack), -> { send(:"#{pack}_statement", d) }]
            end
          end

          # ---- methods: every kind of parameter, and calls that fit ----

          # A method that the units call: its name, and how to call it
          # (a lambda that writes the arguments).
          Def = Struct.new(:name, :args)

          def setup_methods
            rng.rand(2..5).times do
              name = fresh("m")
              shape = pick(%i[plain optional rest keywords block endless forward recursive rescue_ensure yield])
              top(method_def(name, shape))
            end
          end

          def method_def(name, shape)
            case shape
            when :plain
              @defs << Def.new(name, ->(d) { "#{value(:int, d)}, #{value(:int, d)}" })
              "def #{name}(a, b)\n  return a - b if a > b\n  a * 2 + b\nend"
            when :optional
              @defs << Def.new(name, ->(d) { pick(["", value(:int, d), "#{value(:int, d)}, #{value(:int, d)}"]) })
              "def #{name}(a = 3, b = a * 2) = a + b"
            when :rest
              @defs << Def.new(name, ->(d) { Array.new(rng.rand(2..4)) { value(:int, d) }.join(", ") })
              "def #{name}(first, *rest, last)\n  first * 100 + rest.sum * 10 + last\nend"
            when :keywords
              @defs << Def.new(name, ->(d) { "#{value(:int, d)}, k: #{value(:int, d)}#{", z: 1" if chance?(0.3)}" })
              "def #{name}(a, k:, j: 2, **opts)\n  a + k * j + opts.sum { |_, v| v }\nend"
            when :block
              @defs << Def.new(name, ->(d) { value(:int, d) })
              "def #{name}(n, &blk)\n  blk ? blk.call(n) + n : (block_given? ? 1 : -n)\nend"
            when :endless
              @defs << Def.new(name, ->(d) { value(:int, d) })
              "def #{name}(x) = x.#{pick(%w[abs succ pred])} * #{int(1..5)}"
            when :forward
              inner = fresh("m")
              @defs << Def.new(name, ->(d) { "#{value(:int, d)}, #{value(:int, d)}" })
              "def #{inner}(a, b = 1) = a * b - 1\ndef #{name}(...) = #{inner}(...)"
            when :recursive
              @defs << Def.new(name, ->(_) { int(0..15).to_s })
              # The bound is in the method, as a call can pass any Integer.
              "def #{name}(n) = n < 2 || n > 18 ? n : #{name}(n - 1) + #{name}(n - 2)"
            when :rescue_ensure
              @defs << Def.new(name, ->(d) { value(:int, d) })
              "$log = []\ndef #{name}(x)\n  $log << :start\n  10 / x\nrescue ZeroDivisionError\n  $log << :rescued\n  -1\n" \
                "else\n  $log << :else\n  x\nensure\n  $log << :ensure\nend"
            when :yield
              @defs << Def.new(name, ->(d) { value(:int, d) })
              "def #{name}(n)\n  return n unless block_given?\n  yield(n) + yield(n + 1)\nend"
            end
          end

          # A call of one of the methods, as an Integer expression.
          def call_def(d)
            defn = pick(@defs)
            "#{defn.name}(#{defn.args.call(d)})"
          end

          def methods_statement(d)
            return show(d) if @defs.empty?

            defn = pick(@defs)
            weighted([
              [3, -> { "__show(\"#{label}\", #{call_def(d)})" }],
              [1, -> { "__show(\"#{label}\", #{defn.name}(#{defn.args.call(d)}) { |v| v * 2 })" }],
              [1, -> { "__show(\"#{label}\", method(:#{defn.name}).#{pick(%w[arity parameters name owner])})" }],
              [1, -> { "__show(\"#{label}\", #{defn.name}(#{pick(["", "1, 2, 3, 4, 5", "k: 1", "nil"])}))" }],
              [1, -> { "__show(\"#{label}\", [#{value(:int, d)}, #{value(:int, d)}].then { |a, b| #{defn.name}(*[a, b].first(#{int(1..2)})) })" }],
              [1, -> { "__show(\"#{label}\", $log) if defined?($log) && $log" }],
              [1, -> { "__show(\"#{label}\", send(:#{defn.name}, #{defn.args.call(d)}))" }]
            ])
          end

          # ---- blocks: closures, procs, lambdas ----

          def blocks_statement(d)
            c = fresh("c")
            weighted([
              [2, -> { "#{c} = 0\nincr =-> { #{c} += #{value(:int, d)} }\n#{int(1..4)}.times { incr.() }\n__show(\"#{label}\", #{c})" }],
              [1, -> { "__show(\"#{label}\", #{pick(["proc { |a, b| [a, b] }.call([1, 2])", "proc { |a, b| [a, b] }.call(1)", "proc { |a| a }.call(1, 2)", "->(a, b = 2) { [a, b] }.(1)", "proc { |*a| a }.call([1, 2])", "proc { |a, (b, c)| [a, b, c] }.call(1, [2, 3])"])})" }],
              [1, -> { "__show(\"#{label}\", [#{pick(%w[proc\ {} lambda\ {} ->(x){} proc\ {\ |x,\ y|\ } ->(*a,\ b){} proc\ {\ |x,\ y=1|\ }])}].map { |f| [f.arity, f.lambda?] })" }],
              [1, -> { "__show(\"#{label}\", [1, 2, 3].map { it * #{value(:int, d)} })" }],
              [1, -> { "__show(\"#{label}\", [[1, 2], [3, 4]].map { _1 + _2 })" }],
              [1, -> { "__show(\"#{label}\", [[1, 2], [3, 4]].map { |a, b| a * b })" }],
              [1, -> { "__show(\"#{label}\", ->(a, b, c) { a + b + c }.curry[1][2][#{value(:int, d)}])" }],
              [1, -> { "__show(\"#{label}\", (#{proc_literal} >> ->(v) { v * 2 }).call(#{value(:int, d)}))" }],
              [1, -> { "def #{c}_m = [1, 2, 3].each { |x| return x * 10 if x == 2 }\n__show(\"#{label}\", #{c}_m)" }],
              [1, -> { "#{c} = proc { next #{value(:int, d)}; 0 }\n__show(\"#{label}\", #{c}.call)" }],
              [1, -> { "#{c} = [1, 2].each_with_object([]) { |x, a| a << x * 3 }\n__show(\"#{label}\", #{c})" }],
              [1, -> { "#{c} = :upcase.to_proc\n__show(\"#{label}\", [#{c}.call(\"ab\"), #{c}.arity, #{c}.lambda?])" }],
              [1, -> { "#{c} = 5\n[1].each { |x; #{c}| #{c} = x }\n__show(\"#{label}\", #{c})" }],
              [1, -> { "__show(\"#{label}\", Object.new.instance_exec(#{value(:int, d)}) { |v| [v, self.class] })" }],
              [1, -> { "__show(\"#{label}\", [3, 1, 2].sort_by(&:-@).map(&#{pick(%w[:to_s :succ method(:__opaque)])}))" }]
            ])
          end

          # ---- objects: classes, modules, Struct, Data ----

          def setup_objects
            base = fresh("C")
            sub = fresh("C")
            mod = fresh("M")
            @classes << base << sub
            top(<<~RUBY.chomp)
              module #{mod}
                def greet = "hi from \#{self.class.name}"
                def self.included(base) = (@hosts ||= []) << base.name
                def self.hosts = @hosts
              end

              class #{base}
                include Comparable
                attr_reader :a, :b
                attr_accessor :note
                LIMIT = #{int(1..9)}
                @@made = 0

                def self.made = @@made
                def self.build(n) = new(n, n + 1)

                def initialize(a, b = 0)
                  @a = a
                  @b = b
                  @@made += 1
                end

                def <=>(other) = [a, b] <=> [other.a, other.b]
                def ==(other) = other.is_a?(#{base}) && a == other.a && b == other.b
                alias eql? ==
                def hash = [a, b].hash
                def sum = a + b
                def to_s = "#{base}(\#{a}, \#{b})"
                def peek(other) = other.secret
                def deconstruct = [a, b]
                def deconstruct_keys(_keys) = { a: a, b: b }

                protected def secret = a * 2
                private def hidden = :hidden

                def method_missing(name, *args)
                  name.to_s.start_with?("get_") ? "got \#{name.to_s.delete_prefix("get_")}" : super
                end

                def respond_to_missing?(name, include_private = false) = name.to_s.start_with?("get_") || super
              end

              class #{sub} < #{base}
                include #{mod}

                def initialize(a, b = 0, c = 1)
                  super(a, b)
                  @c = c
                end

                def sum = super + @c
                def to_s = "#{sub}:" + super
                def inspect = "#<#{sub} \#{a} \#{b} \#{@c}>"
              end

              #{fresh("S").tap { |s| @classes << s }} = Struct.new(:x, :y) do
                def norm = x.abs + y.abs
              end
              #{fresh("D").tap { |s| @classes << s }} = Data.define(:w, :h) do
                def area = w * h
              end
            RUBY
          end

          def objects_statement(d)
            return show(d) if @classes.empty?

            base, sub, struct, data = @classes
            o = fresh("o")
            weighted([
              [2, -> { "#{o} = #{base}.new(#{value(:int, d)}, #{value(:int, d)})\n__show(\"#{label}\", [#{o}.sum, #{o}.to_s, #{o}.a])" }],
              [2, -> { "#{o} = #{sub}.new(#{value(:int, d)}, #{value(:int, d)}, #{value(:int, d)})\n__show(\"#{label}\", [#{o}.sum, #{o}.to_s, #{o}.greet, #{o}])" }],
              [1, -> { "__show(\"#{label}\", [#{base}.new(3), #{base}.new(1, 9), #{sub}.new(2)].#{pick(%w[sort max min minmax])}.then { |r| Array(r).map(&:to_s) })" }],
              [1, -> { "__show(\"#{label}\", #{base}.new(#{value(:int, d)}).#{pick(["hidden", "secret", "get_name", "respond_to?(:get_x)", "respond_to?(:hidden)", "note", "between?(#{base}.new(0), #{base}.new(9))"])})" }],
              [1, -> { "__show(\"#{label}\", #{base}.new(1).peek(#{sub}.new(4)))" }],
              [1, -> { "__show(\"#{label}\", #{sub}.ancestors.take(4))" }],
              [1, -> { "__show(\"#{label}\", [#{base}.made.class, #{base}::LIMIT, #{sub}::LIMIT, #{sub}.superclass, #{sub}.include?(Comparable)])" }],
              [1, -> { "__show(\"#{label}\", { #{base}.new(1, 2) => :x }[#{base}.new(1, 2)])" }],
              [1, -> { "__show(\"#{label}\", #{base}.instance_methods(false).sort)" }],
              [1, -> { "#{o} = #{base}.new(#{value(:int, d)})\n#{o}.note = #{value(:str, d)}\n__show(\"#{label}\", [#{o}.note, #{o}.instance_variables, #{o}.frozen?, #{o}.dup.note])" }],
              [1, -> { "#{o} = #{base}.build(#{value(:int, d)}).freeze\n__show(\"#{label}\", [#{o}.frozen?, #{o}.clone.frozen?, #{o}.dup.frozen?, #{o}.clone(freeze: false).frozen?])" }],
              [1, -> { "#{o} = #{base}.new(1)\n#{o}.freeze\n#{o}.note = 2" }],
              [1, -> { "#{o} = #{struct}.new(#{value(:int, d)}, #{value(:int, d)})\n__show(\"#{label}\", [#{o}, #{o}.norm, #{o}.to_a, #{o}.members, #{o} == #{struct}.new(*#{o}.to_a), #{o}.to_h])" }],
              [1, -> { "#{o} = #{data}.new(w: #{value(:int, d)}, h: #{value(:int, d)})\n__show(\"#{label}\", [#{o}, #{o}.area, #{o}.with(h: 1), #{o}.to_h])" }],
              [1, -> { "__show(\"#{label}\", #{data}.new(1))" }],
              [1, -> { "__show(\"#{label}\", #{struct}.new(1, 2, 3))" }],
              [1, -> { "__show(\"#{label}\", [#{base}.name, #{sub}.to_s, #{base}.new(1).class, #{struct}.members, #{data}.members])" }],
              [1, -> { "#{o} = Object.new\ndef #{o}.special = :singleton\n__show(\"#{label}\", [#{o}.special, #{o}.singleton_methods, #{o}.singleton_class.instance_methods(false)])" }],
              [1, -> { "__show(\"#{label}\", #{o} = Class.new(#{base}) { def sum = -super }.new(2, 3).sum)" }],
              [1, -> { "__show(\"#{label}\", [1, 2.0, \"s\", :y, nil, [], {}, 1..2, #{base}.new(1)].map { |v| v.class.ancestors.include?(Comparable) })" }],
              [1, -> { "__show(\"#{label}\", 5.coerce(2.5) + 1.5.coerce(2))" }]
            ])
          end

          # ---- exceptions ----

          def setup_exceptions
            top(<<~RUBY.chomp)
              class FuzzError < StandardError
                def initialize(msg = "fuzz default") = super
              end
              class FuzzDeep < FuzzError; end
            RUBY
          end

          def exceptions_statement(d)
            e = fresh("e")
            weighted([
              [2, -> { "begin\n  raise #{pick(%w[FuzzDeep FuzzError ArgumentError])}, #{value(:str, d)}\nrescue FuzzError => #{e}\n  __show(\"#{label}\", [#{e}.class, #{e}.message])\nrescue => #{e}\n  __show(\"#{label}\", [:other, #{e}.class])\nend" }],
              [2, -> { "begin\n  #{risky(d)}\nrescue #{pick(%w[StandardError ZeroDivisionError TypeError ArgumentError NoMethodError KeyError IndexError RangeError FloatDomainError])} => #{e}\n  __show(\"#{label}\", [#{e}.class, #{e}.message])\nend" }],
              [1, -> { "#{e} = []\nbegin\n  #{e} << :body\n  #{risky(d)}\n  #{e} << :after\nrescue\n  #{e} << :rescue\nelse\n  #{e} << :else\nensure\n  #{e} << :ensure\nend\n__show(\"#{label}\", #{e})" }],
              [1, -> { "#{e} = 0\nbegin\n  #{e} += 1\n  raise \"again\" if #{e} < #{int(2..4)}\n  __show(\"#{label}\", #{e})\nrescue\n  retry\nend" }],
              [1, -> { "begin\n  begin\n    #{risky(d)}\n  rescue => inner\n    raise FuzzError, \"wrapped\"\n  end\nrescue => #{e}\n  __show(\"#{label}\", [#{e}.message, #{e}.cause&.class, #{e}.cause&.message])\nend" }],
              [1, -> { "__show(\"#{label}\", (#{risky(d)} rescue $!.class))" }],
              [1, -> { "begin\n  #{risky(d)}\nrescue => #{e}\n  __show(\"#{label}\", #{e}.full_message(highlight: false).lines.first)\nend" }],
              [1, -> { "begin\n  #{risky(d)}\nrescue => #{e}\n  __show(\"#{label}\", [#{e}.backtrace&.first, #{e}.backtrace_locations&.first&.lineno])\nend" }],
              [1, -> { "__show(\"#{label}\", [FuzzError.new.message, FuzzDeep.ancestors.take(3), FuzzError.new(\"m\").full_message(highlight: false)])" }],
              [1, -> { "begin\n  exit #{int(0..3)}\nrescue SystemExit => #{e}\n  __show(\"#{label}\", [#{e}.status, #{e}.success?, #{e}.message])\nend" }],
              [1, -> { "begin\n  throw :nowhere\nrescue UncaughtThrowError => #{e}\n  __show(\"#{label}\", [#{e}.message, #{e}.tag])\nend" }],
              [1, -> { "#{e} = [1, 2].each\n3.times { #{e}.next }" }],
              [1, -> { "__show(\"#{label}\", begin; #{risky(d)}; rescue => #{e}; #{e}.detailed_message(highlight: false); end)" }],
              [1, -> { "#{e} = lambda do\n  return 1\nensure\n  puts \"#{label} ensure\"\nend\n__show(\"#{label}\", #{e}.call)" }],
              [1, -> { "warn(#{value(:str, d)})" }],
              [1, -> { "raise #{pick(['"plain"', "FuzzDeep", 'TypeError, "typed"', 'FuzzError.new("made")', "IOError"])}" }]
            ])
          end

          # An expression that raises often, each time with a message that
          # ruby defines.
          def risky(d)
            pick([
              "#{value(:int, d)} / #{pick(%w[0 1 2])}", "Integer(#{pick(['"x1"', '"12"', '""', "nil", '"0b2"'])})",
              "nil.#{pick(%w[upcase + size])}", "[1, 2].fetch(#{int(-4..4)})", "{ a: 1 }.fetch(#{pick(%w[:a :b "a"])})",
              "Float(#{pick(['"1.2.3"', '"1e"', '"2.5"'])})", "\"abc\".frozen? && \"abc\".freeze << \"d\"", "[1, 2].first(-1)",
              "#{value(:float, d)}.to_i", "\"x\" + #{value(:int, d)}", "#{value(:int, d)} + \"x\"", "[3, \"a\"].sort",
              ":sym.unknown_method", "Comparable.new", "String.new(5)", "Hash.new(1) { }", "\"\u00e9\".encode(\"ASCII\")",
              "[1, 2, 3].first(\"2\")", "loop { raise StopIteration }", "1.upto", "Struct.new(:a).new(1, 2)", "\"%d\" % \"x\"",
              "\"abc\".to_sym.to_proc.call(1)", "Object.const_get(:Nope)", "BasicObject.new.inspect", "def x = 1; x(1)",
              "Rational(1, 0)", "-1.0.digits", "\"a\" * -1", "[].sample(-1)", "\"%z\" % 1", "1.step(10, 0).first(2)"
            ])
          end

          # ---- pattern matching ----

          def pattern_statement(d)
            subject = value(pick(%i[int ints hash str sym]), d)
            arms = [
              "in Integer => n if n > #{int(-2..10)}", "in Integer | Float => n", "in [] ", "in [Integer => first, *rest]",
              "in [*, #{int(0..5)}, *post]", "in {a: Integer => av}", "in {a:, **rest}", "in String => s unless s.empty?",
              "in Symbol", "in [_, _]", "in ^(#{int(0..5)})", "in #{int(-1..3)}..#{int(4..9)}", "in nil",
              "in {b: [*, Integer]}", "in [Integer, Integer] | [String]", "in {}", "in [[*], *]"
            ].sample(rng.rand(1..4), random: rng)
            r = fresh("r")
            text = "#{r} = case #{subject}\n#{arms.map { "#{_1}\n  #{int(0..99)}" }.join("\n")}\n"
            text += chance?(0.7) ? "else\n  :no\nend" : "end"
            weighted([
              [4, -> { "#{text}\n__show(\"#{label}\", #{r})" }],
              [1, -> { "__show(\"#{label}\", (#{subject} in #{pick(["[Integer, *]", "Integer", "{a: 1}", "String", "[]"])}))" }],
              [1, -> { "#{subject} => #{pick(["Integer => z", "[Integer => z, *]", "{a: z}", "String => z"])}\n__show(\"#{label}\", z)" }],
              [1, -> { "case #{@classes.first ? "#{@classes.first}.new(#{value(:int, d)}, 3)" : "[1, 3]"}\nin [x, 3] then __show(\"#{label}\", x)\nin {a:} then __show(\"#{label}\", a)\nend" }]
            ])
          end

          # ---- meta: reflection and definitions at run time ----

          def setup_meta
            r = fresh("R")
            @refinement = r
            top(<<~RUBY.chomp)
              module #{r}
                refine Integer do
                  def fuzz_twice = self * 2
                  #{"def to_s = \"refined\"" if chance?(0.3)}
                end
              end
              using #{r}
              class Object
                def self.method_added(name)
                  (@added ||= []) << name if name.to_s.start_with?("meta_")
                end
              end
            RUBY
          end

          def meta_statement(d)
            o = fresh("o")
            k = fresh("K")
            weighted([
              [2, -> { "#{o} = Class.new do\n  #{%w[a b c].map { |n| "define_method(:#{n}) { |x = 1| x * #{int(1..5)} }" }.join("\n  ")}\nend.new\n__show(\"#{label}\", [#{o}.a, #{o}.b(2), #{o}.respond_to?(:c), #{o}.class.instance_methods(false).sort])" }],
              [1, -> { "#{o} = Object.new\n#{o}.instance_variable_set(:@x, #{value(:int, d)})\n__show(\"#{label}\", [#{o}.instance_variable_get(:@x), #{o}.instance_variables, #{o}.instance_variable_defined?(:@y)])" }],
              [1, -> { "__show(\"#{label}\", [#{value(:int, d)}.send(:+, 1), #{value(:str, d)}.public_send(:upcase), 5.__send__(:-, 2), [1, 2].send(:map) { _1 * 3 }])" }],
              [1, -> { "__show(\"#{label}\", Object.new.public_send(:puts))" }],
              [1, -> { "#{k} = Module.new { def mod_m = :from_module }\n#{o} = Object.new.extend(#{k})\n__show(\"#{label}\", [#{o}.mod_m, #{o}.singleton_class.include?(#{k}), #{o}.is_a?(#{k})])" }],
              [1, -> { "Object.const_set(:#{k}, #{value(:int, d)})\n__show(\"#{label}\", [Object.const_get(:#{k}), Object.const_defined?(:#{k}), defined?(#{k})])" }],
              [1, -> { "#{o} = 3.method(:+)\n__show(\"#{label}\", [#{o}.call(4), #{o}.arity, #{o}.owner, #{o}.name, #{o}.unbind.bind(10).call(1), #{o}.receiver])" }],
              [1, -> { "#{o} = String.instance_method(:upcase)\n__show(\"#{label}\", [#{o}.bind_call(\"ab\"), #{o}.owner, #{o}.name])" }],
              [1, -> { "#{o} = Object.new\n#{o}.define_singleton_method(:dyn) { |a, b = 2| a + b }\n__show(\"#{label}\", [#{o}.dyn(1), #{o}.method(:dyn).arity, #{o}.singleton_methods])" }],
              [1, -> { "class #{k}\n  alias_method :meta_old, :to_s\n  def meta_new = \"new\"\n  attr_writer :w\nend\n__show(\"#{label}\", [#{k}.new.meta_new, #{k}.public_method_defined?(:meta_old), #{k}.instance_variable_get(:@added)])" }],
              [1, -> { @refinement ? "__show(\"#{label}\", [#{value(:int, d)}.fuzz_twice, 7.to_s, \"\#{7}\", 7.respond_to?(:fuzz_twice), [1, 2].map(&:fuzz_twice)])" : show(d) }],
              [1, -> { "#{o} = Object.new\nclass << #{o}\n  def in_singleton = :yes\n  attr_accessor :acc\nend\n#{o}.acc = #{value(:int, d)}\n__show(\"#{label}\", [#{o}.in_singleton, #{o}.acc])" }],
              [1, -> { "__show(\"#{label}\", [Integer.instance_method(:+).owner, Kernel.instance_method(:puts).owner, Comparable.instance_methods.sort.first(3), method(:__show).owner])" }],
              [1, -> { "__show(\"#{label}\", [#{value(:str, d)}.then { |s| s.singleton_class? rescue s.class }, Integer.singleton_class?, Integer.singleton_class.singleton_class?])" }],
              [1, -> { "#{o} = Struct.new(:a)\n#{o}.class_eval { def doubled = a * 2 }\n__show(\"#{label}\", #{o}.new(#{value(:int, d)}).doubled)" }]
            ])
          end

          # ---- eval and Binding ----

          def eval_statement(d)
            x = fresh("x")
            weighted([
              [2, -> { "__show(\"#{label}\", eval(#{value(:int, 1).dump}))" }],
              [1, -> { "#{x} = #{value(:int, d)}\n__show(\"#{label}\", eval(\"#{x} * 2 + 1\"))" }],
              [1, -> { "#{x} = #{value(:int, d)}\nb = binding\nb.local_variable_set(:#{x}, 99)\n__show(\"#{label}\", [#{x}, b.local_variable_get(:#{x}), b.local_variable_defined?(:#{x})])" }],
              [1, -> { "b = binding\nb.local_variable_set(:fresh_#{x}, 5)\n__show(\"#{label}\", [b.local_variable_get(:fresh_#{x}), b.local_variable_defined?(:fresh_#{x})])" }],
              [1, -> { "__show(\"#{label}\", eval(\"[__FILE__, __LINE__]\", nil, \"virtual.rb\", #{int(1..50)}))" }],
              [1, -> { "__show(\"#{label}\", eval(\"__FILE__\"))" }],
              [1, -> { "__show(\"#{label}\", Object.new.instance_eval(\"self.class\"))" }],
              [1, -> { "#{x} = Class.new\n#{x}.class_eval(\"def from_eval(a) = a * #{int(1..9)}\")\n__show(\"#{label}\", #{x}.new.from_eval(#{value(:int, d)}))" }],
              [1, -> { "eval(#{pick(["1 +", "def (", "[1, 2", "end", '"open']).dump})" }],
              [1, -> { "#{x} = 1\n#{x}_b = proc { #{x} += 1; binding }.call\n__show(\"#{label}\", [#{x}_b.local_variable_get(:#{x}), #{x}_b.local_variables.include?(:#{x})])" }],
              [1, -> { "__show(\"#{label}\", eval(\"y = 3; y * 2\"))" }],
              [1, -> { "__show(\"#{label}\", binding.eval(\"defined?(nope_#{x})\"))" }]
            ])
          end

          # ---- fibers, enumerators, threads, ractors ----

          def fiber_thread_statement(d)
            f = fresh("f")
            weighted([
              [2, -> { "#{f} = Fiber.new do |x|\n  y = Fiber.yield x * 2\n  z = Fiber.yield y + 1\n  [x, y, z]\nend\n__show(\"#{label}\", [#{f}.resume(#{value(:int, d)}), #{f}.resume(#{value(:int, d)}), #{f}.resume(:last), #{f}.alive?])" }],
              [1, -> { "#{f} = Fiber.new { :done }\n#{f}.resume\n#{f}.resume" }],
              [2, -> { "#{f} = Enumerator.new do |y|\n  y << 1 << 2\n  y.yield 3, 4\n  y.yield(#{value(:int, d)})\nend\n__show(\"#{label}\", [#{f}.next, #{f}.peek, #{f}.next, #{f}.next, #{f}.take(2), #{f}.size, #{f}.rewind.next])" }],
              [1, -> { "#{f} = #{value(:ints, d)}.each\nloop { __show(\"#{label}\", #{f}.next) }\n__show(\"#{label}\", :end)" }],
              [1, -> { "__show(\"#{label}\", (1..Float::INFINITY).lazy.map { _1 * #{int(1..4)} }.select(&:even?).first(#{int(0..5)}))" }],
              [1, -> { "__show(\"#{label}\", #{value(:ints, d)}.each_slice(2).with_index.map { |s, i| s.sum * i })" }],
              [1, -> { "__show(\"#{label}\", [Thread.new { #{value(:int, d)} }.value, Thread.new { Thread.current[:k] = 1; Thread.current[:k] }.value, Thread.current[:k]])" }],
              [1, -> { "#{f} = Queue.new\nThread.new { 3.times { |i| #{f} << i * 2 }; #{f}.close }.join\n__show(\"#{label}\", [#{f}.pop, #{f}.pop, #{f}.pop, #{f}.pop, #{f}.closed?])" }],
              [1, -> { "#{f} = Mutex.new\n__show(\"#{label}\", [#{f}.synchronize { #{value(:int, d)} }, #{f}.locked?, #{f}.owned?])" }],
              [1, -> { "Fiber[:fz] = #{value(:int, d)}\n__show(\"#{label}\", [Fiber[:fz], Fiber.new { Fiber[:fz] }.resume, Thread.new { Fiber[:fz] }.value])" }],
              [1, -> { "#{f} = Thread.new { raise IOError, \"from a thread\" }\n#{f}.report_on_exception = false\nbegin\n  #{f}.join\nrescue => e\n  __show(\"#{label}\", e.class.superclass)\nend" }],
              [1, -> { "#{f} = Ractor.new(#{value(:int, d)}) { |n| n * 2 }\n__show(\"#{label}\", #{f}.value)" }],
              [1, -> { "#{f} = %w[a b c].each_with_index\n__show(\"#{label}\", [#{f}.next, #{f}.size, #{f}.to_a.last, #{f}.class])" }],
              [1, -> { "#{f} = Enumerator.produce(1) { |x| x * #{int(2..3)} }\n__show(\"#{label}\", #{f}.take(#{int(0..6)}))" }],
              [1, -> { "#{f} = [4, 5].each_with_index.to_a + [6].each.with_index(1).to_a\n__show(\"#{label}\", #{f})" }],
              [1, -> { "#{f} = Fiber.new { Fiber.yield 1; raise \"in fiber\" }\n__show(\"#{label}\", [#{f}.resume, (#{f}.resume rescue $!.message), #{f}.alive?])" }]
            ])
          end

          # ---- collections, strings, numbers beyond the core types ----

          def collections_statement(d)
            weighted([
              [2, -> { "__show(\"#{label}\", #{value(:ints, d)}.#{pick(%w[each_slice(2).to_a each_cons(2).to_a combination(2).to_a permutation(2).first(4) product([0]) group_by(&:even?) partition(&:odd?) chunk(&:odd?).to_a minmax sum.divmod(3) tally sort.reverse each_entry.to_a zip([9]) inject(:+) rotate(-1)])})" }],
              [1, -> { "__show(\"#{label}\", #{value(:hash, d)}.#{pick(%w[to_a invert min_by(&:last) sum{|k,v|v} group_by{|k,v|v.odd?} partition{|k,v|v>1} sort_by(&:last) find{|k,v|v>0} each_with_index.to_a any?{|k,v|v.zero?} keys values count to_a.transpose filter_map{|k,v|k}])})" }],
              [1, -> { "#{(h = fresh("h"))} = Hash.new { |hash, key| hash[key] = key.to_s * 2 }\n#{h}[:ab]\n#{h}[3]\n__show(\"#{label}\", [#{h}, #{h}.default_proc.arity, #{h}.fetch(:zz, 0)])" }],
              [1, -> { "__show(\"#{label}\", [1, [2, [3, [4]]]].flatten(#{int(0..3)}))" }],
              [1, -> { "__show(\"#{label}\", [[3, \"c\"], [1, \"a\"], [3, \"b\"]].sort.map(&:last))" }],
              [1, -> { "__show(\"#{label}\", [0.1, 3, 2r, 1.5r, Complex(1, 1).abs, -0.0, 7].#{pick(%w[sort max min sum minmax])})" }],
              [1, -> { "require \"set\"\n__show(\"#{label}\", Set[#{value(:int, d)}, 2, 3].#{pick(%w[to_a size add?(2) add?(9) subset?(Set[1]) |(Set[5]) &(Set[2,9]) sort])})" }],
              [1, -> { "__show(\"#{label}\", #{value(:ints, d)}.each_with_object(Hash.new(0)) { |x, h| h[x.odd?] += 1 })" }],
              [1, -> { "__show(\"#{label}\", ObjectSpace::WeakMap.new.then { |w| w.key?(1) })" }],
              [1, -> { "__show(\"#{label}\", (#{value(:range, d)}).#{pick(%w[to_a step(2).to_a each_slice(2).to_a minmax sum reverse_each.first(2) step(3).to_a count(&:even?)])})" }],
              [1, -> { "__show(\"#{label}\", [#{value(:ints, d)}].flatten.then { |a| a.dig(0) })" }],
              [1, -> { "__show(\"#{label}\", { a: { b: [10, 20] } }.dig(:a, :b, #{int(-2..2)}))" }],
              [1, -> { "__show(\"#{label}\", Array(#{pick(%w[nil 1 [2] 1..3 {a:\ 1} "s"])}))" }],
              [1, -> { "__show(\"#{label}\", #{value(:ints, d)}.sum { |x| x.fdiv(3) }.round(#{int(0..6)}))" }]
            ])
          end

          def strings_statement(d)
            s = fresh("s")
            weighted([
              [2, -> { "#{s} = #{value(:str, d)}\n__show(\"#{label}\", [#{s}.encoding, #{s}.valid_encoding?, #{s}.bytesize, #{s}.length, #{s}.ascii_only?])" }],
              [1, -> { "#{s} = #{value(:str, d)}.encode(#{pick(['"UTF-16LE"', '"UTF-16BE"', '"ISO-8859-1", undef: :replace', '"Shift_JIS", invalid: :replace, undef: :replace', '"US-ASCII", undef: :replace, replace: "?"'])})\n__show(\"#{label}\", [#{s}.encoding, #{s}.bytes.first(6), #{s}.valid_encoding?])" }],
              [1, -> { "__show(\"#{label}\", \"\\xff\\xfe\".#{pick(%w[valid_encoding? scrub scrub("?") force_encoding("BINARY") inspect bytes unpack("U*") encode("UTF-16LE")])})" }],
              [1, -> { "__show(\"#{label}\", #{value(:str, d)}.each_grapheme_cluster.to_a)" }],
              [1, -> { "__show(\"#{label}\", \"Straße ǅ İ ß\".#{pick(%w[upcase downcase capitalize swapcase upcase(:ascii) downcase(:fold) casecmp?("STRASSE")])})" }],
              [1, -> { "__show(\"#{label}\", #{value(:str, d)}.#{pick(%w[sum unpack("a2a2") each_line.to_a partition("o") rpartition("o") squeeze("a-z") succ.succ ord.chr encode("UTF-8").b each_byte.first(3) tr_s("a-z","*") delete_prefix("a") delete_suffix("c") casecmp("ABC") start_with?(/[a-z]/) byteindex("b") byteslice(1,2) insert(-1,"$") between?("a","z")])})" }],
              [1, -> { "__show(\"#{label}\", format(#{pick(['"%-+08.3f|"', '"%#o %#b %#X"', '"%5.1s|%-5s|"', '"%3$s %1$s %2$s"', '"%c%c"', '"%010.4e"', '"%.0f %.0f %.0f"', '"% x"'])}, *#{pick(["[3.14159]", "[255, 5, 255]", '["abc", "de"]', '["a", "b", "c"]', '[65, "z"]', "[12345.678]", "[0.5, 1.5, 2.5]", "[-255]"])}))" }],
              [1, -> { "__show(\"#{label}\", <<~HEREDOC)\n  line \#{#{value(:int, d)}}\n    indented\n  done\nHEREDOC" }],
              [1, -> { "__show(\"#{label}\", <<-'RAW')\n  raw \#{not} \\n\n  RAW" }],
              [1, -> { "__show(\"#{label}\", [\"%s\" % nil, \"%p\" % [nil], \"%-5s|\" % :sym, \"%05.1f\" % 2.25, \"%x\" % -255, \"%e\" % 0.0])" }],
              [1, -> { "__show(\"#{label}\", #{value(:str, d)}.match(/(?<first>\\w)(?<rest>\\w*)/)&.then { |m| [m[:first], m[\"rest\"], m.pre_match, m.names, m.captures, m.begin(0)] })" }],
              [1, -> { "if #{value(:str, d)} =~ /(\\w)(\\w)/\n  __show(\"#{label}\", [$~[0], $1, $2, $`, $', Regexp.last_match(1)])\nend" }],
              [1, -> { "__show(\"#{label}\", [/a+/i.source, /x/m.options, Regexp.escape(\"a.b*c\"), Regexp.union(\"a\", /b/), /\#{#{value(:int, d)}}/ =~ \"x12\"])" }],
              [1, -> { "__show(\"#{label}\", #{value(:str, d)}.gsub(/(?<v>[aeiou])/, '[\\k<v>]'))" }],
              [1, -> { "__show(\"#{label}\", #{value(:str, d)}.unpack(#{pick(['"C*"', '"U*"', '"a3"', '"Z*"', '"H4"', '"m"', '"b8"', '"n"', '"s<"'])}))" }],
              [1, -> { "__show(\"#{label}\", [#{value(:str, d)}].pack(#{pick(['"m"', '"m0"', '"u"', '"H*"', '"A5"', '"a5"', '"Z*"', '"M"'])}))" }],
              [1, -> { "__show(\"#{label}\", #{value(:sym, d)}.#{pick(%w[inspect length upcase to_proc.call("ab").to_s <=>(:m) start_with?("a") end_with?("e") encoding [](0) size succ])})" }]
            ])
          end

          def numeric_statement(d)
            weighted([
              [2, -> { "__show(\"#{label}\", [#{value(:int, d)}.to_r, Rational(#{value(:int, d)}, #{nonzero(d)}), #{value(:float, d)}.rationalize(Rational(1, 100)), 3r / 4 + 1, 0.75.to_r])" }],
              [1, -> { "__show(\"#{label}\", [Complex(#{value(:int, d)}, #{value(:int, d)}), Complex(1, 2) * Complex(3, -1), Complex(\"1+2i\"), 2i ** 2, Complex(3, 4).abs, Complex(1, 1).arg.round(4)])" }],
              [2, -> { "__show(\"#{label}\", #{value(:float, d)}.#{pick(%w[round(half:\ :even) round(half:\ :up) round(half:\ :down) round(1,\ half:\ :even) floor(2) ceil(-1) to_r divmod(0.5) modulo(-1.5) remainder(-1.5) truncate(3) next_float.round(15) prev_float.round(15) to_s inspect])})" }],
              [1, -> { "__show(\"#{label}\", [2.5.round, 3.5.round, -2.5.round, 2.675.round(2), 1.15.round(1), 0.1 + 0.2, 1.0 / 3, 1e23, 1e22, 9007199254740993, 123456789.123456789])" }],
              [1, -> { "__show(\"#{label}\", [Float::MAX * 2, -Float::MAX * 2, 0.0 / 0.0, (0.0 / 0.0).to_s, 1 / -0.0, -0.0.to_s, 1e-320, 5e-324.prev_float])" }],
              [1, -> { "__show(\"#{label}\", (2**#{int(60..130)}).then { |b| [b, b.to_s(16), b.bit_length, b / 7, b % 1000, -b >> 3, b.digits(1000).first(2), b.to_f, Integer.sqrt(b)] })" }],
              [1, -> { "__show(\"#{label}\", [#{value(:int, d)}.pow(#{int(10..40)}), (-7).divmod(2), 7.divmod(-2), -7 % 3, -7.remainder(3), 7.fdiv(2), 2**-2, 4**0.5, (-8)**(1.0/3)])" }],
              [1, -> { "__show(\"#{label}\", [#{value(:int, d)}.to_s.rjust(10, \"0\"), 1234567.89.to_s, 1e15.to_i, 12.3e-5, 100.0.to_s, 1e16.to_s, 1.23456789012345e+15])" }],
              [1, -> { "__show(\"#{label}\", [Integer === 2**70, (2**70).class, (2**70).hash.class, 2**64 == 2.0**64, 2**53 + 1 == (2**53 + 1).to_f, 10**25 <=> 1e25])" }],
              [1, -> { "__show(\"#{label}\", [Random.new(#{int(0..99)}).rand(100), Random.new(#{int(0..99)}).rand, Random.new(1).bytes(4).bytes, Random.new(2).rand(1.5..2.5)])" }],
              [1, -> { "__show(\"#{label}\", [Math.sqrt(2), Math::PI.round(10), Math.log(8, 2), Math.atan2(1, -1), Math.gamma(5), Math.lgamma(3), Math.frexp(1234.0), Math.ldexp(0.5, 3)])" }],
              [1, -> { "__show(\"#{label}\", [1.0.to_s, 1.5e300 * 1e10, 100.0.floor(-2), 15.round(-1), 25.round(-1, half: :even), 0.1 * 3, 1.23.truncate(1), -1.5.ceil, 12.34.divmod(5)])" }],
              [1, -> { "__show(\"#{label}\", [#{value(:int, d)}.integer?, 3.0.integer?, 3.7 % 1, 10.gcdlcm(4), 255.digits(16), 6.lcm(4), 10.pred.succ, 3.zero?, 0.0.zero?, -0.0 == 0.0, 0.1r])" }]
            ])
          end

          # ---- the standard library ----

          STDLIBS = {
            "json" => ["JSON.generate(%v)", "JSON.pretty_generate({ \"a\" => [1, 2.5, nil, true], \"b\" => { \"c\" => \"é\\n\" } })",
                       "JSON.parse('{\"a\": [1, 2.50, null, \"\\\\u00e9\"], \"b\": 1e3}')", "%v.to_json",
                       "(JSON.parse('[1, 2', symbolize_names: true) rescue $!.class)", "JSON.dump(%v)",
                       "JSON.parse('{\"k\": 1}', symbolize_names: true)", "JSON.generate(\"\\u2028<>&\")"],
            "stringio" => ["StringIO.new.tap { |io| io.puts 1, [2, 3]; io.print :x; io.printf(\"%03d\", 7) }.string",
                           "StringIO.new(\"a\\nb\\nc\").each_line.map(&:chomp)", "StringIO.new(\"abcdef\").tap { |io| io.seek(2) }.read(3)",
                           "StringIO.new(\"x y\").gets(\" \")"],
            "strscan" => ["StringScanner.new(\"3 apples, 12 pears\").then { |s| [s.scan(/\\d+/), s.scan(/\\s+/), s.scan(/\\w+/), s.pos, s.rest, s.eos?] }",
                          "StringScanner.new(\"key=val\").then { |s| [s.scan_until(/=/), s.pre_match, s.matched, s.check(/\\w+/)] }"],
            "date" => ["Date.new(2024, 2, 29).then { |d| [d.to_s, (d >> 12).to_s, d.yday, d.cwday, d.leap?, (d + 1).to_s] }",
                       "Date.parse(\"2026-10-12\").then { |d| [d.strftime(\"%a %b %-d %Y %j\"), d.next_month.to_s, d.mjd] }",
                       "(Date.new(2020, 1, 1)..Date.new(2020, 1, 5)).map(&:day)", "Date.valid_date?(2023, 2, 29)",
                       "DateTime.new(2001, 2, 3, 4, 5, 6).iso8601"],
            "digest" => ["Digest::MD5.hexdigest(%s)", "Digest::SHA256.hexdigest(%s)", "Digest::SHA1.base64digest(%s)"],
            "base64" => ["Base64.strict_encode64(%s)", "Base64.urlsafe_encode64(%s, padding: false)", "Base64.decode64(\"aGVsbG8=\")"],
            "shellwords" => ["Shellwords.split(%(a \"b c\" d\\\\ e))", "%s.shellescape", "[\"a b\", \"c\"].shelljoin"],
            "erb" => ["ERB.new(\"<%% 3.times do |i| %%><%%= i %%>,<%% end %%>\").result", "ERB.new(\"x=<%%= 1 + 2 %%>\").result"],
            "time" => ["Time.at(%i).utc.then { |t| [t.year, t.iso8601, t.strftime(\"%%Y-%%m-%%d %%H:%%M:%%S %%z %%A\"), t.wday] }",
                       "Time.utc(2000, 1, 2, 3, 4, 5.5).then { |t| [t.usec, t.to_f, (t + 86400).day, t.inspect] }",
                       "Time.iso8601(\"2026-10-12T10:20:30Z\").to_i", "Time.at(0, 123456, :usec, in: \"UTC\").inspect"],
            "pp" => ["PP.pp({ a: [1] * 20, b: \"x\" * 30 }, +\"\", 30)", "%v.pretty_inspect"],
            "optparse" => ["OptionParser.new { |o| o.on(\"-v\", \"--verbose\"); o.on(\"-nNAME\") }.parse(%w[-v -n x rest])",
                           "begin; OptionParser.new.parse(%w[--nope]); rescue OptionParser::InvalidOption => e; e.message; end"],
            "zlib" => ["Zlib.crc32(%s)", "Zlib.adler32(%s)", "Zlib::Inflate.inflate(Zlib::Deflate.deflate(%s))"],
            "prime" => ["Prime.first(%n)", "Prime.prime?(%i % 100_000)", "(%i % 10_000).abs.prime_division"],
            "forwardable" => ["Class.new { extend Forwardable; def_delegators :@a, :size, :first; def initialize = @a = [3, 4] }.new.then { [_1.size, _1.first] }"],
            "delegate" => ["SimpleDelegator.new([1, 2]).then { |d| [d.size, d.__getobj__.class, d.map { _1 * 2 }] }"],
            "securerandom" => ["SecureRandom.hex(4).size"],
            "matrix" => ["Matrix[[1, 2], [3, 4]].then { |m| [m.determinant, (m * m).to_a, m.transpose.to_a] }"],
            "tsort" => ["{ 1 => [2, 3], 2 => [3], 3 => [], 4 => [1] }.then { |h| TSort.tsort(h.method(:each_key), ->(n, &b) { h[n].each(&b) }) }"]
          }.freeze

          def setup_stdlib
            @libs = STDLIBS.keys.sample(rng.rand(1..4), random: rng)
            @libs.each { |lib| require!(lib) }
          end

          def stdlib_statement(d)
            lib = pick(@libs)
            expr = pick(STDLIBS.fetch(lib)).gsub(/%[vsin%]/) do |slot|
              case slot
              when "%v" then value(pick(%i[ints hash strs str int]), d)
              when "%s" then value(:str, d)
              when "%i" then value(:int, d)
              when "%n" then int(0..8).to_s
              when "%%" then "%"
              end
            end
            "__show(\"#{label}\", #{expr})"
          end

          # ---- the collector: objects that must survive collections ----

          def gc_pressure_statement(d)
            keep = fresh("keep")
            weighted([
              [2, -> { "#{keep} = #{value(:ints, d)}.map { |x| [x, x.to_s * 3, { k: x }] }\n#{int(500..3000)}.times { |i| \"junk\#{i}\" * 3 }\nGC.start\n__show(\"#{label}\", #{keep})" }],
              [1, -> { "#{keep} = Hash.new { |h, k| h[k] = k.to_s * 2 }\n#{int(200..2000)}.times { |i| #{keep}[i % 50]; [i] * 4 }\nGC.start(full_mark: true)\n__show(\"#{label}\", #{keep}.size)" }],
              [1, -> { "#{keep} = (1..#{int(100..900)}).map { |i| proc { i * 2 } }\nGC.start\n__show(\"#{label}\", #{keep}.sum(&:call))" }],
              [1, -> { "#{keep} = Fiber.new { a = Array.new(1000) { |i| i.to_s }; Fiber.yield 0; a.size }\n#{keep}.resume\nGC.start\n__show(\"#{label}\", #{keep}.resume)" }],
              [1, -> { "#{keep} = +\"\"\n#{int(100..2000)}.times { |i| #{keep} << (i % 10).to_s; #{keep}.dup }\nGC.compact rescue nil\n__show(\"#{label}\", [#{keep}.size, #{keep}[-5..]])" }],
              [1, -> { "#{keep} = Struct.new(:a, :b)\n#{keep}_all = Array.new(#{int(200..1500)}) { |i| #{keep}.new(i, [i]) }\nGC.start\n__show(\"#{label}\", #{keep}_all.sum { _1.b.first })" }]
            ])
          end

          # ---- explore: any public method of a value, with any arguments ----

          def explore_statement(d)
            type = pick(%i[int float str sym ints strs hash range])
            receiver = value(type, d)
            name = Catalog.pick(type, rng) or return show(d)
            args = Array.new(Catalog.arg_count(type, name, rng)) { pick(Catalog::ARGS) }
            "__show(\"#{label}\", #{receiver}.public_send(:#{name}#{args.map { ", #{_1}" }.join}))"
          end

          # ---- the ending: how the program stops ----

          def ending_code
            pick([
              "at_exit { puts \"at_exit 1\" }\nat_exit { puts \"at_exit 2\" }\nputs \"main done\"",
              "raise FuzzEnd = Class.new(StandardError), \"the end\"",
              "raise ArgumentError",
              "def deep_end(n) = n.zero? ? raise(\"deep\") : deep_end(n - 1)\ndeep_end(#{int(1..5)})",
              "exit #{int(0..5)}",
              "exit!(#{int(0..3)})",
              "abort \"aborted\"",
              "$stderr.puts \"to stderr\"\nexit 1",
              "throw :not_caught",
              "at_exit { exit 7 }\nputs :before",
              "[1, 2].each { |x| raise \"in block \#{x}\" if x == 2 }",
              "Integer(\"zz\")",
              "$stdout.sync = true\nputs 1\nwarn 2\nputs 3\nexit false"
            ])
          end
        end
      end
    end
  end
end
# rubocop:enable Layout/LineLength, Lint/PercentStringArray
