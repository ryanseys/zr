# frozen_string_literal: true

# The lines of this file are templates of Ruby source: long, and with the
# quotes of the source in them.
# rubocop:disable Layout/LineLength

module Zr
  module Dev
    module Fuzz
      module Gen
        # The statements of a unit: new locals, changes to them, output,
        # and control flow. Every loop has a bound that the writer knows.
        # The packs (Packs) add statements of their own, by weight.
        module Statements
          def statement(d)
            weighted([
              [5, -> { assign(d) }],
              [6, -> { show(d) }],
              [2, -> { update(d) }],
              [3, -> { control(d) }],
              *pack_statements(d)
            ])
          end

          # A new local, or a new value for a local of the same type.
          def assign(d)
            type = pick(TYPES)
            expr = value(type, d)
            old = local(type)
            return "#{old} = #{expr}" if old && chance?(0.2)

            name = fresh
            text = "#{name} = #{expr}"
            bind(type, name)
            text
          end

          # Prints a value, in one of the ways a program prints.
          def show(d)
            type = pick(TYPES)
            expr = value(type, d)
            weighted([
              [8, "__show(\"#{label}\", #{expr})"],
              [2, "p(#{expr})"],
              [2, "puts(#{expr})"],
              [1, "print(#{expr}, \"\\n\")"],
              [1, "pp(#{expr})"],
              [1, "$stdout.puts(#{expr}.inspect)"],
              [1, "$stdout << \"#{label} \" << #{expr}.to_s << \"\\n\""],
              [1, "printf(\"%s %p\\n\", #{expr}, #{expr})"],
              [1, "puts [#{expr}, #{value(pick(TYPES), d)}].inspect"],
              [1, "puts \"#{label}: \#{(#{expr}).inspect}\""],
              [1, "STDOUT.write(#{expr}.to_s, \"\\n\")"],
              [1, "$stdout.print(\"#{label} \", #{expr}.inspect, \"\\n\")"]
            ])
          end

          # A change to a local that exists: an op-assign, or a method that
          # changes it in place (on a copy, as a literal may be frozen).
          def update(d)
            type = pick(%i[int ints str hash float bool])
            name = local(type) or return assign(d)
            case type
            when :int
              chance?(0.15) ? "#{name} #{pick(%w[<<= >>=])} #{int(0..8)}" : "#{name} #{pick(%w[+= -= *= ||= &&= |= ^=])} #{value(:int, d)}"
            when :float then "#{name} #{pick(%w[+= -= *= /=])} #{value(:float, d)}"
            when :bool then "#{name} #{pick(%w[||= &&=])} #{value(:bool, d)}"
            when :ints then "#{name} = #{name}.dup\n#{name}#{change(ARRAY_CHANGES, d)}"
            when :str then "#{name} = +#{name}.to_s\n#{name}#{change(STRING_CHANGES, d)}"
            when :hash then "#{name} = #{name}.dup\n#{name}#{change(HASH_CHANGES, d)}"
            end
          end

          # Changes in place, as the text after the receiver. `%i`, `%a`,
          # `%s` and `%h` stand for an Integer, an Array, a String and a
          # Hash expression.
          ARRAY_CHANGES = [".push(%i)", " << %i", ".unshift(%i)", ".insert(1, %i)", ".concat(%a)", ".delete_at(-1)", ".delete(%i)",
                           ".sort!", ".reverse!", ".map! { |x| x + 1 }", ".select!(&:even?)", ".uniq!", ".fill(7, 1)", ".shift(2)",
                           ".pop", ".rotate!(2)", ".slice!(1, 2)", "[0] = %i", "[1..2] = [%i]", ".keep_if { |x| x > 0 }", ".clear",
                           ".sort_by! { -_1 }", ".flatten!", ".compact!", ".replace(%a)"].freeze
          STRING_CHANGES = [" << %s", ".concat(%s, \"!\")", ".upcase!", ".insert(0, %s)", ".prepend(\"<\")", ".replace(%s)",
                            ".squeeze!", ".sub!(/./, \"_\")", ".gsub!(\"l\", \"L\")", ".tr!(\"a-m\", \"n-z\")", "[0] = \"Z\"",
                            ".slice!(0, 2)", ".chomp!(\"d\")", ".succ!", ".reverse!", ".force_encoding(\"BINARY\")", ".clear",
                            "[-1, 1] = %s", ".setbyte(0, 65)", ".capitalize!", ".swapcase!"].freeze
          HASH_CHANGES = ["[:a] = %i", "[\"b\"] = %i", ".delete(:a)", ".delete(\"a\")", ".store(:k, %i)", ".merge!(%h)",
                          ".transform_values!(&:succ)", ".select! { |_, v| v.odd? }", ".compact!", ".default = %i", ".update(q: 1)",
                          ".shift", ".clear", ".compare_by_identity", ".rehash", ".delete_if { |k, _| k.to_s < \"b\" }",
                          ".transform_keys!(&:to_s)", ".filter_map { |k, v| k if v }"].freeze

          def change(list, d)
            pick(list).gsub(/%[iash]/) do |slot|
              value({ "%i" => :int, "%a" => :ints, "%s" => :str, "%h" => :hash }.fetch(slot), d)
            end
          end

          # A body of `n` statements in a new block scope.
          def body(d, n = rng.rand(1..3))
            scoped { Array.new(n) { statement(d) }.join("\n") }
          end

          def control(d)
            return show(d) if d <= 0

            d -= 1
            weighted([
              [3, -> { "if #{value(:bool, d)}\n#{indent(body(d))}\n#{pick(["else\n#{indent(body(d))}\n", "elsif #{value(:bool, d)}\n#{indent(body(d))}\n", ""])}end" }],
              [1, -> { "unless #{value(:bool, d)}\n#{indent(body(d))}\nend" }],
              [2, -> { "#{show(d)} #{pick(%w[if unless])} #{value(:bool, d)}" }],
              [2, -> { case_when(d) }],
              [2, -> { times_loop(d) }],
              [2, -> { each_loop(d) }],
              [1, -> { while_loop(d) }],
              [1, -> { for_loop(d) }],
              [1, -> { loop_with_break(d) }],
              [1, -> { break_value(d) }],
              [1, -> { catch_throw(d) }],
              [1, -> { "begin\n#{indent(body(d))}\nend while false" }],
              [1, -> { flip_flop(d) }]
            ])
          end

          def case_when(d)
            subject = value(:int, d)
            arms = Array.new(rng.rand(1..4)) do
              test = pick(["#{int(-2..5)}", "#{int(-2..2)}..#{int(3..9)}", "Integer", "->(x) { x.odd? }", "#{int(0..3)}, #{int(4..7)}",
                           "*[#{int(0..9)}, #{int(0..9)}]", "Float", "(10..)", "..0"])
              "when #{test}\n#{indent(body(d, 1))}"
            end
            "case #{subject}\n#{arms.join("\n")}\n#{"else\n#{indent(body(d, 1))}\n" if chance?(0.6)}end"
          end

          def times_loop(d)
            i = fresh("i")
            inner = scoped do
              bind(:int, i)
              Array.new(rng.rand(1..2)) { statement(d) }.join("\n")
            end
            "#{int(0..4)}.#{pick(["times", "upto(#{int(0..4)})", "downto(-1)"])} do |#{i}|\n#{indent(inner)}\nend"
          end

          def each_loop(d)
            x = fresh("x")
            acc = fresh("acc")
            src = value(:ints, d)
            inner = scoped do
              bind(:int, x)
              ["#{acc} #{pick(%w[+= -= ^=])} #{x}", *Array.new(rng.rand(0..1)) { statement(d) }].join("\n")
            end
            meth = pick(%w[each each_with_index reverse_each each_entry])
            params = meth == "each_with_index" ? "#{x}, _idx" : x
            bind(:int, acc)
            "#{acc} = 0\n#{src}.#{meth} do |#{params}|\n#{indent(inner)}\nend\n__show(\"#{label}\", #{acc})"
          end

          def while_loop(d)
            i = fresh("i")
            inner = scoped do
              Array.new(rng.rand(1..2)) { statement(d) }.join("\n")
            end
            bind(:int, i)
            kind = pick(%w[while until])
            cond = kind == "while" ? "#{i} < #{int(1..6)}" : "#{i} >= #{int(1..6)}"
            "#{i} = 0\n#{kind} #{cond}\n#{indent(inner)}\n  #{i} += 1\n#{"  next if #{i} == 2\n" if chance?(0.2)}end"
          end

          # `for` binds its variable in the enclosing scope, so it is a
          # local after the loop.
          def for_loop(d)
            x = fresh("f")
            src = value(pick(%i[ints range]), d)
            inner = scoped do
              bind(:int, x)
              statement(d)
            end
            out = "for #{x} in #{src}\n#{indent(inner)}\nend\n__show(\"#{label}\", #{x})"
            bind(:int, x)
            out
          end

          def loop_with_break(d)
            n = fresh("n")
            inner = scoped { statement(d) }
            bind(:int, n)
            "#{n} = 0\nloop do\n  #{n} += 1\n  break if #{n} > #{int(1..5)}\n#{indent(inner)}\nend\n__show(\"#{label}\", #{n})"
          end

          def break_value(d)
            x = fresh("x")
            r = fresh("r")
            inner = scoped do
              bind(:int, x)
              "break(#{value(:int, d)}) if #{value(:bool, d)}\nnext if #{x}.odd?\n#{x} * 2"
            end
            "#{r} = #{value(:ints, d)}.#{pick(%w[each map find select])} do |#{x}|\n#{indent(inner)}\nend\n__show(\"#{label}\", #{r})"
          end

          def catch_throw(d)
            i = fresh("i")
            r = fresh("r")
            inner = scoped do
              bind(:int, i)
              "throw :done, #{value(:int, d)} if #{value(:bool, d)}"
            end
            "#{r} = catch(:done) do\n  #{int(0..5)}.times do |#{i}|\n#{indent(inner, 2)}\n  end\n  :never\nend\n__show(\"#{label}\", #{r})"
          end

          def flip_flop(_d)
            a = int(0..4)
            b = a + int(0..4)
            # A flip-flop is one only in a condition.
            "__show(\"#{label}\", (0..9).select { |i| ((i == #{a})#{pick(%w[.. ...])}(i == #{b})) ? true : false })"
          end
        end
      end
    end
  end
end
# rubocop:enable Layout/LineLength
