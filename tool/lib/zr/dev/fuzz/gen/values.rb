# frozen_string_literal: true

# The lines of this file are templates of Ruby source: long, and with the
# quotes of the source in their %w lists.
# rubocop:disable Layout/LineLength, Lint/PercentStringArray

module Zr
  module Dev
    module Fuzz
      module Gen
        # Expressions of each type (Writer::TYPES). `value(type, d)` gives
        # source that evaluates to a value of `type`, nested at most `d`
        # deep. At depth 0 it gives a literal or a local. An expression
        # may still raise (a division by zero, a nil from an index): that
        # is defined behavior, and the unit prints the error.
        module Values
          def value(type, d = 2)
            return leaf(type) if d <= 0 || chance?(0.25)

            known = local(type)
            return known if known && chance?(0.3)

            send(:"#{type}_expr", d - 1)
          end

          def leaf(type)
            known = local(type)
            return known if known && chance?(0.6)

            send(:"#{type}_literal")
          end

          # --- literals ---

          SMALL_INTS = [0, 1, 2, 3, 5, 7, 10, 12, 42, 100, -1, -2, -7, 255, 256].freeze
          BIG_INTS = %w[(2**31) (2**32) (2**62) (2**63) (2**64) (2**64+1) (10**18) (10**20) (-(2**63)) (-(2**64)) (3**40)
                        0x7fff_ffff 1_000_000 0b1011 0o777 0xff].freeze

          def int_literal
            return pick(BIG_INTS) if chance?(0.12)

            n = pick(SMALL_INTS)
            n.negative? ? "(#{n})" : n.to_s
          end

          FLOATS = %w[0.0 1.0 0.5 2.5 3.75 (-1.5) 0.1 1e10 1.5e-5 1e100 123.456 (1.0/3) 100.0 (-0.0) 2.0e-308 9007199254740993.0
                      1e16 0.30000000000000004].freeze

          def float_literal
            chance?(0.05) ? pick(%w[Float::NAN Float::INFINITY (-Float::INFINITY) Float::EPSILON Float::MAX]) : pick(FLOATS)
          end

          STRINGS = ['"abc"', '"hello world"', '""', '"a,b,,c"', '"Ruby"', '"  spaced  "', '"x"', '"日本語"', '"ünïcödé"',
                     '"tab\\there"', '"line1\\nline2"', '"quote\\"d"', %q('single #{not}'), '"a-b_c d"', '"MiXeD"', '"12345"',
                     '"0x1F"', '"3.14"', '"😀 emoji"', '"\\u00e9"', '"\\x41\\x42"', '"%d%%"', '"a.b.c"', '"aaa"', '"zebra"',
                     "%q(paren's)", '%Q(dq #{1 + 1})', "?a", '"\\e[0m"'].freeze

          def str_literal
            text = pick(STRINGS)
            return "\"#{leaf_bits}\"" if chance?(0.15)

            text
          end

          # The text of an interpolated string, with a leaf or two in it.
          def leaf_bits
            Array.new(rng.rand(1..2)) { "#{pick(%w[a - = : x])}\#{#{leaf(pick(%i[int str sym float]))}}" }.join
          end

          SYMBOLS = [":a", ":b", ":name", ":size", ":to_s", ":upcase", ":+", ":<=>", ":[]", ":a?", ":b!", ":Const", ":@iv", ":$gv", ':"with space"'].freeze

          def sym_literal = pick(SYMBOLS)

          def bool_literal = pick(%w[true false])

          def ints_literal
            return "[]" if chance?(0.1)
            return pick(["(1..#{int(2..6)}).to_a", "Array.new(#{int(1..5)}) { |i| i * #{int(1..4)} }", "[*1..#{int(2..5)}]"]) if chance?(0.2)

            "[#{Array.new(rng.rand(1..6)) { int_literal }.join(", ")}]"
          end

          def strs_literal
            return "%w[#{Array.new(rng.rand(1..5)) { pick(%w[a b c ab ba cab xyz Q zz é]) }.join(" ")}]" if chance?(0.4)

            "[#{Array.new(rng.rand(0..4)) { str_literal }.join(", ")}]"
          end

          def hash_literal
            n = rng.rand(0..4)
            return "{}" if n.zero?

            keys = %w[a b c d e f].sample(n, random: rng)
            if chance?(0.5)
              "{ #{keys.map { |k| "#{k}: #{int_literal}" }.join(", ")} }"
            else
              "{ #{keys.map { |k| "\"#{k}\" => #{int_literal}" }.join(", ")} }"
            end
          end

          def range_literal
            a = int(-3..5)
            b = a + int(0..6)
            chance?(0.5) ? "(#{a}..#{b})" : "(#{a}...#{b})"
          end

          def proc_literal
            x = fresh("x")
            body = scoped do
              bind(:int, x)
              int_expr(1)
            end
            pick(["->(#{x}) { #{body} }", "lambda { |#{x}| #{body} }", "proc { |#{x}| #{body} }", "method(:__opaque)",
                  ":succ.to_proc", ":abs.to_proc"])
          end

          # --- one block parameter of `type`, and a body of `out` ---

          # A block `{ |p| body }` whose parameter has type `param` and whose
          # body gives `out`. Sometimes it uses `it` or `_1`.
          def block_of(param, out, d)
            name = fresh("e")
            body = scoped do
              bind(param, name)
              value(out, d)
            end
            # `it` and `_1` cannot stand in a block that has a block in it.
            plain = !body.match?(/[{|]|\bdo\b/)
            case plain ? rng.rand(10) : 9
            when 0 then "{ #{body.gsub(/\b#{name}\b/, "it")} }"
            when 1 then "{ #{body.gsub(/\b#{name}\b/, "_1")} }"
            else "{ |#{name}| #{body} }"
            end
          end

          # --- expressions ---

          def int_expr(d)
            weighted([
              [6, -> { "(#{value(:int, d)} #{pick(%w[+ - *])} #{value(:int, d)})" }],
              [2, -> { "(#{value(:int, d)} #{pick(%w[/ %])} #{nonzero(d)})" }],
              [1, -> { "#{value(:int, d)}.#{pick(%w[divmod(%s).first fdiv(%s).floor div(%s) modulo(%s) remainder(%s)])}".gsub("%s", nonzero(d)) }],
              [1, -> { "(#{small_int} ** #{int(0..70)})" }],
              [2, -> { "#{value(:int, d)}.#{pick(%w[abs pred succ bit_length -@ ~ ord])}" }],
              [1, -> { "#{value(:int, d)}.digits.sum" }],
              [2, -> { "#{value(:str, d)}.#{pick(%w[size length bytesize count("a") to_i hex sum ord])}" }],
              [3, -> { "#{value(:ints, d)}.#{pick(%w[size sum count min max first last length])}.to_i" }],
              [1, -> { "#{value(:ints, d)}.sum #{block_of(:int, :int, d)}" }],
              [1, -> { "#{value(:ints, d)}.inject(#{int_literal}) { |a, b| a #{pick(%w[+ - * ^ |])} b }" }],
              [1, -> { "#{value(:ints, d)}.count #{block_of(:int, :bool, d)}" }],
              [1, -> { "#{value(:hash, d)}.#{pick(%w[size length count])}" }],
              [1, -> { "#{value(:hash, d)}.values.sum" }],
              [1, -> { "#{value(:range, d)}.#{pick(%w[size count sum min max first last])}.to_i" }],
              [2, -> { "[#{value(:int, d)}, #{value(:int, d)}].#{pick(%w[max min sum])}" }],
              [1, -> { "#{value(:int, d)}.clamp(-5, 50)" }],
              [1, -> { "#{value(:int, d)}.#{pick(%w[gcd lcm])}(#{nonzero(d)})" }],
              [1, -> { "#{value(:int, d)}.pow(#{int(0..30)}, #{int(1..1000)})" }],
              [1, -> { "(#{value(:int, d)} <=> #{value(:int, d)})" }],
              [1, -> { "#{value(:int, d)}[#{int(0..70)}]" }],
              [1, -> { "(#{value(:int, d)} #{pick(%w[<< >> & | ^])} #{int(0..66)})" }],
              [2, -> { "#{value(:float, d)}.#{pick(%w[round floor ceil to_i truncate])}" }],
              [1, -> { "#{value(:float, d)}.round(#{int(-2..3)}).to_i" }],
              [1, -> { "Integer.sqrt(#{value(:int, d)}.abs)" }],
              [1, -> { "Integer(#{pick(['"0x1f"', '"0b101"', '"0o17"', '"  42  "', '"1_000"', '"12"', '"-7"'])})" }],
              [1, -> { "(#{value(:bool, d)} ? #{value(:int, d)} : #{value(:int, d)})" }],
              [1, -> { "#{value(:proc, d)}.call(#{value(:int, d)})" }],
              [1, -> { "#{value(:int, d)}.then #{block_of(:int, :int, d)}" }],
              [1, -> { "__opaque(#{value(:int, d)})" }],
              [1, -> { "#{value(:sym, d)}.size" }],
              [1, -> { "#{value(:int, d)}.#{pick(%w[to_s(2) to_s(16) to_s(36) digits.reverse.join])}.size" }],
              [1, -> { "#{value(:ints, d)}.index(#{value(:int, d)}).to_i" }],
              [1, -> { "#{value(:int, d)}.#{pick(%w[floor(-1) ceil(-2) round(-1) truncate(-1) round(-1,\ half:\ :even)])}" }],
              [@defs.empty? ? 0 : 3, -> { call_def(d) }]
            ])
          end

          def small_int = pick(%w[2 3 -2 10 7 -1 0 1])

          # An Integer expression that is not zero, mostly.
          def nonzero(d) = chance?(0.9) ? pick(%w[1 2 3 7 -3 10 16]) : value(:int, d)

          def float_expr(d)
            weighted([
              [3, -> { "(#{value(:float, d)} #{pick(%w[+ - * /])} #{value(:float, d)})" }],
              [2, -> { "#{value(:int, d)}.to_f" }],
              [2, -> { "#{value(:int, d)}.fdiv(#{nonzero(d)})" }],
              [1, -> { "(#{value(:int, d)} / #{value(:float, d)})" }],
              [2, -> { "#{value(:float, d)}.round(#{int(0..4)})" }],
              [1, -> { "#{value(:float, d)}.#{pick(%w[abs -@ next_float prev_float])}" }],
              [1, -> { "Math.#{pick(%w[sqrt cbrt log2 log10 sin cos atan exp])}(#{value(:float, d)}.abs)" }],
              [1, -> { "Math.hypot(#{value(:float, d)}, #{value(:float, d)})" }],
              [1, -> { "Float(#{pick(['"1.5"', '"-0.25"', '"1e3"', '" 2.5 "', '"1_0.5"', '"0x1p3"'])})" }],
              [1, -> { "#{value(:str, d)}.to_f" }],
              [1, -> { "(#{value(:float, d)} % #{pick(%w[1.5 2 0.3 -1.25])})" }],
              [1, -> { "#{value(:float, d)}.#{pick(%w[floor(1) ceil(2) truncate(1)])}.to_f" }],
              [1, -> { "(#{value(:float, d)} ** #{pick(%w[2 0.5 -1 3])})" }],
              [1, -> { "[#{value(:float, d)}, #{value(:float, d)}].#{pick(%w[max min sum])}" }],
              [1, -> { "#{value(:ints, d)}.sum(0.0)" }],
              [1, -> { "#{value(:int, d)}.quo(#{nonzero(d)}).to_f" }]
            ])
          end

          def str_expr(d)
            weighted([
              [3, -> { "#{value(:str, d)}.#{pick(%w[upcase downcase swapcase capitalize reverse strip succ chomp chop squeeze lstrip rstrip])}" }],
              [2, -> { "(#{value(:str, d)} + #{value(:str, d)})" }],
              [1, -> { "(#{value(:str, d)} * #{int(0..3)})" }],
              [3, -> { "\"#{interpolation(d)}\"" }],
              [2, -> { "#{value(:int, d)}.to_s" }],
              [1, -> { "#{value(:int, d)}.to_s(#{pick([2, 8, 16, 36])})" }],
              [2, -> { "#{value(:float, d)}.to_s" }],
              [2, -> { "#{value(:ints, d)}.join(#{pick(['","', '"-"', '""', '" | "'])})" }],
              [1, -> { "#{value(:strs, d)}.join(#{pick(['","', '""', '" "'])})" }],
              [2, -> { "#{pick(%w[ints strs hash range])}".then { |t| "#{value(t.to_sym, d)}.inspect" } }],
              [1, -> { "#{value(:sym, d)}.#{pick(%w[to_s inspect name])}" }],
              [1, -> { "#{value(:str, d)}[#{int(-3..4)}, #{int(0..4)}].to_s" }],
              [1, -> { "#{value(:str, d)}[#{value(:range, d)}].to_s" }],
              [1, -> { "#{value(:str, d)}.#{pick(%w[center ljust rjust])}(#{int(0..14)}, #{pick(['"*"', '"-="', '" "'])})" }],
              [2, -> { format_call(d) }],
              [1, -> { "#{value(:str, d)}.tr(#{pick(['"a-y", "b-z"', '"aeiou", "*"', '"^a-z", "_"', '"lo", "01"'])})" }],
              [1, -> { "#{value(:str, d)}.#{pick(%w[gsub sub])}(#{pick(["/[aeiou]/", '"l"', '/(\w)(\w)/', '/\s+/', "/^./"])}, #{pick(['"*"', '"\\\\2\\\\1"', '"<\\\\0>"', '""'])})" }],
              [1, -> { "#{value(:str, d)}.gsub(/\\w/) { |m| m.#{pick(%w[upcase ord.to_s succ])} }" }],
              [1, -> { "#{value(:str, d)}.#{pick(%w[delete squeeze count])}(#{pick(['"l"', '"a-c"', '"^a"'])}).to_s" }],
              [1, -> { "#{value(:str, d)}.chars.#{pick(%w[sort reverse rotate uniq shuffle(random:\ Random.new(3))])}.join" }],
              [1, -> { "#{value(:str, d)}.#{pick(%w[unpack1("H*") unpack1("b*") unpack("C*").inspect encoding.to_s b.inspect dump])}" }],
              [1, -> { "#{value(:str, d)}.scan(#{pick(['/\w/', "/[a-z]+/", "/./", "/(.)(.)/"])}).inspect" }],
              [1, -> { "#{value(:str, d)}.#{pick(%w[each_char.to_a.inspect bytes.inspect codepoints.inspect lines.inspect split.inspect])}" }],
              [1, -> { "#{value(:str, d)}.split(#{pick(['","', '""', '/,\s*/', '" ", 2', '",", -1'])}).inspect" }],
              [1, -> { "#{value(:str, d)}.#{pick(%w[start_with?("a") end_with?("d") include?("o") match?(/\d/) ascii_only? valid_encoding?])}.to_s" }],
              [1, -> { "#{value(:str, d)}.#{pick(%w[unicode_normalize(:nfd) encode("UTF-16LE").bytesize.to_s force_encoding("BINARY").inspect])}" }],
              [1, -> { "#{value(:str, d)}.slice(#{int(0..3)}..).to_s" }],
              [1, -> { "#{value(:str, d)}.#{pick(%w[ljust(3).inspect hash.class.to_s frozen?.to_s dup.concat("!") +@.concat("?")])}" }],
              [1, -> { "(#{value(:bool, d)} ? #{value(:str, d)} : #{value(:str, d)})" }],
              [1, -> { "#{value(:str, d)} % #{pick(["[1, 2]", "{ a: 3 }", '"x"', "3.5"])}".then { |e| "(#{e} rescue \"fmt\")" } }],
              [1, -> { "#{value(:ints, d)}.pack(#{pick(['"C*"', '"n*"', '"U*"', '"N*"', '"w*"'])}).inspect" }]
            ])
          end

          def interpolation(d)
            Array.new(rng.rand(1..3)) { "#{pick(["", "a", " = ", ", ", "\\t", "é"])}\#{#{value(pick(TYPES - %i[proc]), d)}}" }.join
          end

          def format_call(d)
            fmt, args = pick([
              ["%05d|%-4s|%x", -> { [value(:int, d), value(:str, d), "#{value(:int, d)}.abs"] }],
              ["%.3f %e", -> { [value(:float, d), value(:float, d)] }],
              ["%+d %o %b", -> { [value(:int, d), "#{value(:int, d)}.abs", "#{value(:int, d)}.abs"] }],
              ["%s and %p", -> { [value(:str, d), value(:sym, d)] }],
              ["%10.4s|%-6.2f|%c", -> { [value(:str, d), value(:float, d), "65 + #{value(:int, d)}.abs % 26"] }],
              ["%<a>s-%<b>d", -> { ["a: #{value(:str, d)}", "b: #{value(:int, d)}"] }],
              ["%08.3f|% d|%#x", -> { [value(:float, d), value(:int, d), "#{value(:int, d)}.abs"] }],
              ["%g %G %a", -> { [value(:float, d), value(:float, d), value(:float, d)] }]
            ])
            "format(#{fmt.inspect}, #{args.call.join(", ")})"
          end

          def sym_expr(d)
            weighted([
              [2, -> { "#{value(:str, d)}.to_sym" }],
              [1, -> { "#{value(:sym, d)}.#{pick(%w[upcase succ swapcase downcase])}" }],
              [1, -> { "%i[#{Array.new(3) { pick(%w[a b c dd]) }.join(" ")}].#{pick(%w[first last min max])}" }],
              [1, -> { "(#{value(:hash, d)}.keys.first&.to_sym || :none)" }],
              [1, -> { "(#{value(:bool, d)} ? #{sym_literal} : #{sym_literal})" }]
            ])
          end

          def bool_expr(d)
            weighted([
              [4, -> { "(#{value(:int, d)} #{pick(%w[< <= > >= == != ===])} #{value(:int, d)})" }],
              [2, -> { "#{value(:int, d)}.#{pick(%w[even? odd? zero? positive? negative? nonzero?.nil? integer? finite?])}" }],
              [2, -> { "#{value(:str, d)}.#{pick(%w[empty? frozen? ascii_only?])}" }],
              [1, -> { "#{value(:str, d)}.#{pick(%w[include? start_with? end_with? eql? ==])}(#{value(:str, d)})" }],
              [1, -> { "#{value(:ints, d)}.include?(#{value(:int, d)})" }],
              [1, -> { "#{value(:ints, d)}.#{pick(%w[any? all? none? one?])} #{block_of(:int, :bool, d)}" }],
              [1, -> { "#{value(:ints, d)}.#{pick(%w[empty? frozen? any? none?])}" }],
              [1, -> { "#{value(:hash, d)}.#{pick(%w[key? include? member?])}(#{pick(%w[:a :b "a" "c"])})" }],
              [1, -> { "#{value(:range, d)}.#{pick(%w[cover? include? ===])}(#{value(:int, d)})" }],
              [2, -> { "!#{value(:bool, d)}" }],
              [2, -> { "(#{value(:bool, d)} #{pick(%w[&& || and or ^ &])} #{value(:bool, d)})" }],
              [1, -> { "#{value(:float, d)}.#{pick(%w[nan? finite? infinite?.nil? zero?])}" }],
              [1, -> { "#{value(pick(TYPES), d)}.#{pick(%w[nil? frozen? is_a?(Integer) is_a?(Comparable) kind_of?(Enumerable) instance_of?(String) respond_to?(:each)])}" }],
              [1, -> { "#{value(:int, d)}.between?(#{int(-3..2)}, #{int(3..50)})" }],
              [1, -> { "(#{value(:ints, d)} #{pick(%w[== !=])} #{value(:ints, d)})" }],
              [1, -> { "#{value(:ints, d)}.#{pick(%w[eql? equal? ==])}(#{value(:ints, d)})" }],
              [1, -> { "#{value(:str, d)}.match?(#{pick(['/\A[a-z]+\z/', '/\d/', '/^\s/', '/(.)\1/'])})" }],
              [1, -> { "defined?(#{pick(%w[@nope String puts zork $stdout])}).nil?" }]
            ])
          end

          def ints_expr(d)
            weighted([
              [4, -> { "#{value(:ints, d)}.map #{block_of(:int, :int, d)}" }],
              [3, -> { "#{value(:ints, d)}.#{pick(%w[select reject filter take_while drop_while])} #{block_of(:int, :bool, d)}" }],
              [1, -> { "#{value(:ints, d)}.partition #{block_of(:int, :bool, d)}.#{pick(%w[first last])}" }],
              [2, -> { "#{value(:ints, d)}.#{pick(%w[sort_by min_by(2) max_by(2) uniq])} #{block_of(:int, :int, d)}" }],
              [3, -> { "#{value(:ints, d)}.#{pick(%w[sort reverse uniq compact rotate flatten sort.reverse minmax])}" }],
              [2, -> { "#{value(:ints, d)}.#{pick(%w[take drop first last rotate min max])}(#{int(0..4)})" }],
              [1, lambda {
                random = "random: Random.new(#{int(0..9)})"
                "#{value(:ints, d)}.#{pick(["shuffle(#{random})", "sample(#{int(0..3)}, #{random})"])}"
              }],
              [2, -> { "(#{value(:ints, d)} #{pick(%w[+ - & |])} #{value(:ints, d)})" }],
              [1, -> { "(#{value(:ints, d)} * #{int(0..3)})" }],
              [1, -> { "#{value(:str, d)}.#{pick(%w[bytes codepoints])}" }],
              [1, -> { "#{value(:int, d)}.abs.digits" }],
              [1, -> { "#{value(:hash, d)}.values" }],
              [1, -> { "#{value(:range, d)}.to_a" }],
              [1, -> { "#{value(:range, d)}.step(#{int(1..3)}).to_a" }],
              [1, -> { "#{value(:ints, d)}.each_slice(#{int(1..3)}).map(&:sum)" }],
              [1, -> { "#{value(:ints, d)}.each_cons(2).map { |a, b| a - b }" }],
              [1, -> { "#{value(:ints, d)}.each_with_index.map { |x, i| x * i }" }],
              [1, -> { "#{value(:ints, d)}.filter_map { |x| x * 2 if x.even? }" }],
              [1, -> { "#{value(:ints, d)}.zip(#{value(:ints, d)}).map { |a, b| a.to_i + b.to_i }" }],
              [1, -> { "#{value(:ints, d)}.chunk_while { |a, b| b == a + 1 }.map(&:size)" }],
              [1, -> { "#{value(:ints, d)}.slice_when { |a, b| b < a }.map(&:first)" }],
              [1, -> { "#{value(:ints, d)}.group_by(&:odd?).values.flatten" }],
              [1, -> { "#{value(:ints, d)}.tally.values" }],
              [1, -> { "#{value(:ints, d)}.each_with_object([]) { |x, acc| acc.unshift(x) }" }],
              [1, -> { "#{value(:ints, d)}.cycle.first(#{int(0..7)})" }],
              [1, -> { "#{value(:ints, d)}.combination(2).map(&:sum)" }],
              [1, -> { "#{value(:ints, d)}.values_at(0, -1, 2).compact" }],
              [1, -> { "#{value(:ints, d)}.flat_map { |x| [x, -x] }" }],
              [1, -> { "#{value(:ints, d)}.sort { |a, b| b <=> a }" }],
              [1, -> { "#{value(:ints, d)}.lazy.map { _1 * 3 }.select(&:even?).first(#{int(0..4)})" }],
              [1, -> { "#{value(:strs, d)}.map(&:size)" }],
              [1, -> { "Array.new(#{int(0..4)}) #{block_of(:int, :int, d)}" }],
              [1, -> { "#{value(:ints, d)}.dup.tap { |a| a.#{pick(%w[push(9) pop shift unshift(0) sort! reverse! uniq! compact! clear concat([1])])} }" }],
              [1, -> { "#{value(:ints, d)}.sum.then { |s| [s, s * 2] }" }],
              [1, -> { "#{value(:ints, d)}.bsearch { |x| x >= #{int(0..10)} }.then { [_1.to_i] }" }]
            ])
          end

          def strs_expr(d)
            weighted([
              [3, -> { "#{value(:strs, d)}.map #{block_of(:str, :str, d)}" }],
              [2, -> { "#{value(:str, d)}.#{pick(%w[chars lines split])}" }],
              [1, -> { "#{value(:str, d)}.split(#{pick(['","', '""', '/\s+/', "/(,)/"])})" }],
              [2, -> { "#{value(:strs, d)}.#{pick(%w[sort reverse uniq compact sort_by(&:size) select(&:frozen?) map(&:upcase) map(&:succ)])}" }],
              [1, -> { "#{value(:ints, d)}.map(&:to_s)" }],
              [1, -> { "#{value(:ints, d)}.map { |x| x.to_s(2) }" }],
              [1, -> { "#{value(:hash, d)}.keys.map(&:to_s)" }],
              [1, -> { "#{value(:str, d)}.scan(/\\w+/)" }],
              [1, -> { "(#{value(:strs, d)} + #{value(:strs, d)})" }],
              [1, -> { "#{value(:strs, d)}.grep(#{pick(["/a/", '/\A\w\z/', "String", "/[^a-z]/"])})" }],
              [1, -> { "#{value(:strs, d)}.each_slice(2).map(&:join)" }],
              [1, -> { "#{value(:strs, d)}.sort_by { |s| [-s.size, s] }" }]
            ])
          end

          def hash_expr(d)
            weighted([
              [2, -> { "#{value(:ints, d)}.tally.transform_keys(&:to_s)" }],
              [2, -> { "#{value(:hash, d)}.transform_values #{block_of(:int, :int, d)}" }],
              [2, -> { "#{value(:hash, d)}.#{pick(%w[select reject])} { |_k, v| #{bool_on("v", d)} }" }],
              [2, -> { "#{value(:hash, d)}.merge(#{value(:hash, d)})" }],
              [1, -> { "#{value(:hash, d)}.merge(#{value(:hash, d)}) { |_k, a, b| a + b }" }],
              [1, -> { "#{value(:hash, d)}.sort_by { |k, v| [-v, k.to_s] }.to_h" }],
              [1, -> { "#{value(:strs, d)}.to_h { |s| [s, s.size] }" }],
              [1, -> { "#{value(:strs, d)}.each_with_index.to_h" }],
              [1, -> { "#{value(:ints, d)}.group_by { |x| x % 3 }.transform_values(&:sum).transform_keys(&:to_s)" }],
              [1, -> { "#{value(:hash, d)}.to_a.reverse.to_h" }],
              [1, -> { "#{value(:hash, d)}.slice(:a, :b, \"a\")" }],
              [1, -> { "#{value(:hash, d)}.except(:a, \"b\")" }],
              [1, -> { "Hash.new(0).tap { |h| #{value(:strs, d)}.each { |s| h[s] += 1 } }" }],
              [1, -> { "#{value(:hash, d)}.min_by(2) { |_, v| v }.to_h" }],
              [1, -> { "#{value(:hash, d)}.dup.tap { |h| h[#{pick(%w[:z "z" :a])}] = #{value(:int, d)} }" }],
              [1, -> { "#{value(:hash, d)}.dup.tap { |h| h.delete(#{pick(%w[:a "a" :b])}) }" }],
              [1, -> { "#{value(:hash, d)}.filter_map { |k, v| [k, v * 2] if v.odd? }.to_h" }]
            ])
          end

          def bool_on(name, d)
            scoped do
              bind(:int, name)
              bool_expr(d)
            end
          end

          def range_expr(d)
            weighted([
              [2, -> { "(#{value(:int, d)}.clamp(-5, 5)..#{value(:int, d)}.clamp(-5, 9))" }],
              [1, -> { "(#{int(0..3)}...#{value(:ints, d)}.size)" }],
              [1, -> { "Range.new(#{int(-2..2)}, #{int(2..8)}, #{bool_literal})" }],
              [1, -> { "(#{int(0..5)}..).first(#{int(0..5)}).then { |a| a.empty? ? (0..-1) : (a.first..a.last) }" }]
            ])
          end

          def proc_expr(d)
            weighted([
              [2, -> { proc_literal }],
              [1, -> { "(#{value(:proc, d)} >> #{value(:proc, d)})" }],
              [1, -> { "(#{value(:proc, d)} << #{value(:proc, d)})" }],
              [1, -> { "#{value(:proc, d)}.curry" }],
              [1, -> { "method(:__opaque).to_proc" }]
            ])
          end
        end
      end
    end
  end
end
# rubocop:enable Layout/LineLength, Lint/PercentStringArray
