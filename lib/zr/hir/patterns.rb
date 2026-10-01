# frozen_string_literal: true

module Zr
  module Hir
    class Build
      # Pattern matching, as CRuby compiles it: `case/in`, `value => pattern`
      # and `value in pattern` become tests on hidden locals. A test returns
      # true and binds its captures as it runs. A failed check in a
      # single-pattern form records the reason, and the final raise reads it.
      module Patterns
        # A hidden local of the innermost scope.
        def temp(hint)
          @temp_serial = (@temp_serial || 0) + 1
          name = :"%#{hint}#{@temp_serial}"
          @temps.last << name
          name
        end

        def read(name, line) = Local.new(name, 0, line)

        def set(name, value, line) = Assign.new(name, 0, value, line)

        def send_to(recv, name, args, line, **) = Send.of(recv, name, args, line, **)

        # A core class by name. No constant of the program can shadow it.
        def core(name, line) = Core.new(name, line)

        # `!value` on truthiness only, so a program's `!` cannot change it.
        # `until` and an `unless` guard test this, as compile.c branches.
        def falsy(value, line) = If.new(value, Literal.new(false, line), Literal.new(true, line), line)

        # `case value; in pattern [if guard] then body; ...; else other; end`
        def case_match(node, taken: true)
          line = node.location.start_line
          # Number the branches before the chain is built, because the chain
          # is built from the last clause and ruby numbers from the first.
          covers = branch_covers(:case, span(node.location), case_sides(node, :in))
          subject = temp(:subject)
          single = node.conditions.size == 1 && node.else_clause.nil?
          match = Match.new(self, single ? temp(:why) : nil, single ? temp(:key) : nil, single ? temp(:matchee) : nil)
          chain = node.else_clause ? expr(node.else_clause, taken: taken) : no_match(subject, match, line)
          chain = covered(covers.last, chain, line)
          node.conditions.each_with_index.reverse_each do |clause, i|
            test = match.clause(clause.pattern, subject)
            body = clause.statements ? seq(clause.statements, taken: taken) : Literal.new(nil, clause.location.start_line)
            chain = If.new(test, covered(covers[i], body, clause.location.start_line), chain, clause.location.start_line)
          end
          Seq.new([set(subject, expr(node.predicate), line), *match.resets(line), chain], line)
        end

        # `value => pattern`: nil, or the raise.
        def match_required(node)
          line = node.location.start_line
          subject = temp(:subject)
          match = Match.new(self, temp(:why), temp(:key), temp(:matchee))
          test = match.pattern(node.pattern, subject)
          Seq.new([set(subject, expr(node.value), line), *match.resets(line), If.new(test, Literal.new(nil, line), no_match(subject, match, line), line)], line)
        end

        # `value in pattern`: true or false.
        def match_predicate(node)
          line = node.location.start_line
          subject = temp(:subject)
          match = Match.new(self, nil, nil, nil)
          test = match.pattern(node.pattern, subject)
          Seq.new([set(subject, expr(node.value), line), If.new(test, Literal.new(true, line), Literal.new(false, line), line)], line)
        end

        # `/(?<x>.)/ =~ text`: the named groups are assigned to locals (nil if
        # nothing matched). The value is the result of `=~`.
        #
        # One assignment per name, with the group or nil as its value, not
        # one in each branch: ruby binds a named group once, and
        # `Ractor.shareable_proc` counts a local's bindings.
        def match_write(node)
          line = node.location.start_line
          result = temp(:matched)
          match = GvarRead.new(:$~, line)
          writes = node.targets.map do |t|
            group = send_to(match, :[], [Literal.new(t.name, line)], line)
            Assign.new(t.name, t.depth, If.new(match, group, Literal.new(nil, line), line), line)
          end
          Seq.new([set(result, expr(node.call), line), *writes, read(result, line)], line)
        end

        # The raise if nothing matched. After several patterns, the message
        # is only the subject's to_s. After a single pattern, it is the
        # subject's inspect and the recorded reason. For a missing key, it
        # is the key error with its key and matchee.
        def no_match(subject, match, line)
          return send_to(core(:Kernel, line), :raise, [core(:NoMatchingPatternError, line),send_to(read(subject, line), :to_s, [], line)], line) if match.why.nil?

          inspect = send_to(read(subject, line), :inspect, [], line)

          message = Interp.new([inspect, Literal.new(": ", line), read(match.why, line)], line)
          key_error = send_to(core(:NoMatchingPatternKeyError, line), :new, [message], line,
                              kwargs: HashLit.new([Literal.new(:matchee, line), read(match.matchee, line), Literal.new(:key, line), read(match.key, line)], line))
          If.new(read(match.key, line),
                 send_to(core(:Kernel, line), :raise, [key_error], line),
                 send_to(core(:Kernel, line), :raise, [core(:NoMatchingPatternError, line), message], line), line)
        end

        # One match's state: where a failed check records its reason.
        class Match
          attr_reader :why, :key, :matchee

          def initialize(build, why, key, matchee)
            @b = build
            @why = why
            @key = key
            @matchee = matchee
          end

          # The hidden locals cleared before the match runs: the reason,
          # and every deconstruct cache (a loop runs the same case again).
          def resets(line)
            names = (@caches || {}).values
            names += [@why, @key, @matchee] unless @why.nil?
            names.map { |name| @b.set(name, Literal.new(nil, line), line) }
          end

          # An `in` clause's pattern with its guard.
          def clause(node, subject)
            case node
            when Prism::IfNode then guarded(node.statements.body.first, node.predicate, subject, true)
            when Prism::UnlessNode then guarded(node.statements.body.first, node.predicate, subject, false)
            else pattern(node, subject)
            end
          end

          def guarded(pattern_node, predicate, subject, positive)
            line = predicate.location.start_line
            guard = @b.expr(predicate)
            guard = @b.falsy(guard, line) unless positive
            And.new(pattern(pattern_node, subject), failing(guard, Literal.new("guard clause does not return true", line), line), line)
          end

          # The test for `node` against the hidden local `subject`.
          def pattern(node, subject)
            line = node.location.start_line
            case node
            when Prism::ArrayPatternNode then array_pattern(node, subject, line)
            when Prism::FindPatternNode then find_pattern(node, subject, line)
            when Prism::HashPatternNode then hash_pattern(node, subject, line)
            when Prism::AlternationPatternNode then Or.new(pattern(node.left, subject), pattern(node.right, subject), line)
            when Prism::ParenthesesNode then pattern(node.body.is_a?(Prism::StatementsNode) ? node.body.body.first : node.body, subject)
            when Prism::CapturePatternNode
              And.new(pattern(node.value, subject), bind(node.target, @b.read(subject, line), line), line)
            when Prism::LocalVariableTargetNode then bind(node, @b.read(subject, line), line)
            when Prism::PinnedVariableNode then value_pattern(@b.expr(node.variable), subject, line)
            when Prism::PinnedExpressionNode then value_pattern(@b.expr(node.expression), subject, line)
            else value_pattern(@b.expr(node), subject, line)
            end
          end

          # `pattern === subject`. The reason gives both.
          def value_pattern(value, subject, line)
            return @b.send_to(value, :===, [@b.read(subject, line)], line) if @why.nil?

            held = @b.temp(:pattern)
            test = @b.send_to(@b.set(held, value, line), :===, [@b.read(subject, line)], line)
            failing(test, Interp.new([inspect_of(held, line), Literal.new(" === ", line), inspect_of(subject, line), Literal.new(" does not return true", line)], line), line)
          end

          # `x`: the subject bound to the local.
          def bind(target, value, line)
            Seq.new([Assign.new(target.name, target.depth, value, line), Literal.new(true, line)], line)
          end

          # `test`, or false with `reason` recorded.
          def failing(test, reason, line)
            return test if @why.nil?

            Or.new(test, Seq.new([@b.set(@why, reason, line), @b.set(@key, Literal.new(nil, line), line), Literal.new(false, line)], line), line)
          end

          def inspect_of(name, line) = @b.send_to(@b.read(name, line), :inspect, [], line)

          # `Const === subject` if the pattern has a constant.
          def constant_test(node, subject, line)
            node.constant ? [value_pattern(@b.expr(node.constant), subject, line)] : []
          end

          # `subject.deconstruct`, called once per subject and kept: an
          # Array, or a TypeError.
          def deconstructed(subject, line)
            cache = (@caches ||= {})[subject] ||= @b.temp(:deconstructed)
            d = @b.temp(:elements)
            responds = @b.send_to(@b.read(subject, line), :respond_to?, [Literal.new(:deconstruct, line)], line)
            call = Or.new(@b.read(cache, line), @b.set(cache, @b.send_to(@b.read(subject, line), :deconstruct, [], line), line), line)
            typed = If.new(@b.send_to(@b.read(d, line), :is_a?, [@b.core(:Array, line)], line), Literal.new(true, line),
                           @b.send_to(@b.core(:Kernel, line), :raise, [@b.core(:TypeError, line), Literal.new("deconstruct must return Array", line)], line), line)
            steps = [failing(responds, Interp.new([inspect_of(subject, line), Literal.new(" does not respond to #deconstruct", line)], line), line),
                     Seq.new([@b.set(d, call, line), typed], line)]
            [d, steps]
          end

          def element(d, index, line)
            @b.send_to(@b.read(d, line), :[], [index], line)
          end

          def size_of(d, line) = @b.send_to(@b.read(d, line), :size, [], line)

          # `[a, b, *rest, c]`, with an optional constant in front.
          def array_pattern(node, subject, line)
            steps = constant_test(node, subject, line)
            d, ask = deconstructed(subject, line)
            steps.concat(ask)
            pre = node.requireds
            post = node.posts
            rest = node.rest
            n = pre.size + post.size
            length = rest ? @b.send_to(size_of(d, line), :>=, [Literal.new(n, line)], line) : @b.send_to(size_of(d, line), :==, [Literal.new(n, line)], line)
            steps << failing(length, Interp.new([inspect_of(d, line), Literal.new(" length mismatch (given ", line), size_of(d, line), Literal.new(", expected #{n}#{rest ? "+" : ""})", line)], line), line)
            pre.each_with_index { |p, i| steps << nested(p, element(d, Literal.new(i, line), line), line) }
            post.each_with_index do |p, i|
              at = @b.send_to(size_of(d, line), :-, [Literal.new(post.size - i, line)], line)
              steps << nested(p, element(d, at, line), line)
            end
            if rest.is_a?(Prism::SplatNode) && rest.expression
              count = @b.send_to(size_of(d, line), :-, [Literal.new(n, line)], line)
              steps << bind(rest.expression, @b.send_to(@b.read(d, line), :[], [Literal.new(pre.size, line), count], line), line)
            end
            conjunction(steps, line)
          end

          # `[*pre, a, b, *post]`: the first position where the middle matches.
          def find_pattern(node, subject, line)
            steps = constant_test(node, subject, line)
            d, ask = deconstructed(subject, line)
            steps.concat(ask)
            middle = node.requireds
            m = middle.size
            steps << failing(@b.send_to(size_of(d, line), :>=, [Literal.new(m, line)], line), Interp.new([inspect_of(d, line), Literal.new(" does not match to find pattern", line)], line), line)
            i = @b.temp(:at)
            found = @b.temp(:found)
            before = (@caches ||= {}).keys
            tries = middle.each_with_index.map { |p, k| nested(p, element(d, @b.send_to(@b.read(i, line), :+, [Literal.new(k, line)], line), line), line) }
            # Each position that the loop tries is a new subject for the
            # parts, so their deconstruct caches start empty on each iteration.
            fresh = (@caches.keys - before).map { |s| @b.set(@caches[s], Literal.new(nil, line), line) }
            test = If.new(conjunction(tries, line), @b.set(found, Literal.new(true, line), line), @b.set(i, @b.send_to(@b.read(i, line), :+, [Literal.new(1, line)], line), line), line)
            body = Seq.new([*fresh, test], line)
            more = @b.send_to(@b.send_to(@b.read(i, line), :+, [Literal.new(m, line)], line), :<=, [size_of(d, line)], line)
            loop = While.new(And.new(@b.falsy(@b.read(found, line), line), more, line), body, line)
            binds = []
            binds << bind(node.left.expression, @b.send_to(@b.read(d, line), :[], [Literal.new(0, line), @b.read(i, line)], line), line) if node.left.expression
            if node.right.expression
              from = @b.send_to(@b.read(i, line), :+, [Literal.new(m, line)], line)
              binds << bind(node.right.expression, @b.send_to(@b.read(d, line), :[], [from, size_of(d, line)], line), line)
            end
            steps << Seq.new([@b.set(i, Literal.new(0, line), line), @b.set(found, Literal.new(false, line), line), loop,
                              failing(@b.read(found, line), Interp.new([inspect_of(d, line), Literal.new(" does not match to find pattern", line)], line), line)], line)
            steps.concat(binds)
            conjunction(steps, line)
          end

          # `{k: pattern, j:, **rest}`, with an optional constant in front.
          def hash_pattern(node, subject, line)
            steps = constant_test(node, subject, line)
            keys = node.elements.map { |e| e.key.unescaped.to_sym }
            asked = node.rest.nil? && !node.elements.empty? ? ArrayLit.new(keys.map { |k| Literal.new(k, line) }, line) : Literal.new(nil, line)
            d = @b.temp(:pairs)
            responds = @b.send_to(@b.read(subject, line), :respond_to?, [Literal.new(:deconstruct_keys, line)], line)
            steps << failing(responds, Interp.new([inspect_of(subject, line), Literal.new(" does not respond to #deconstruct_keys", line)], line), line)
            typed = If.new(@b.send_to(@b.read(d, line), :is_a?, [@b.core(:Hash, line)], line), Literal.new(true, line),
                           @b.send_to(@b.core(:Kernel, line), :raise, [@b.core(:TypeError, line), Literal.new("deconstruct_keys must return Hash", line)], line), line)
            steps << Seq.new([@b.set(d, @b.send_to(@b.read(subject, line), :deconstruct_keys, [asked], line), line), typed], line)
            if node.elements.empty? && node.rest.nil?
              steps << failing(@b.send_to(@b.read(d, line), :empty?, [], line), Interp.new([inspect_of(d, line), Literal.new(" is not empty", line)], line), line)
            end
            node.elements.each do |e|
              key = Literal.new(e.key.unescaped.to_sym, line)
              steps << key_present(d, key, line)
              value = element(d, key, line)
              steps << if e.value.is_a?(Prism::ImplicitNode)
                         bind(e.value.value, value, line)
                       else
                         nested(e.value, value, line)
                       end
            end
            case node.rest
            when Prism::NoKeywordsParameterNode
              rest = @b.temp(:rest)
              steps << Seq.new([@b.set(rest, without_keys(d, keys, line), line),
                                failing(@b.send_to(@b.read(rest, line), :empty?, [], line), Interp.new([Literal.new("rest of ", line), inspect_of(rest, line), Literal.new(" is not empty", line)], line), line)], line)
            when Prism::AssocSplatNode
              steps << bind(node.rest.value, without_keys(d, keys, line), line) if node.rest.value
            end
            conjunction(steps, line)
          end

          # `d.key?(key)`, else the key error's facts recorded.
          def key_present(d, key, line)
            test = @b.send_to(@b.read(d, line), :key?, [key], line)
            return test if @why.nil?

            Or.new(test, Seq.new([@b.set(@why, Interp.new([Literal.new("key not found: ", line), @b.send_to(key, :inspect, [], line)], line), line),
                                  @b.set(@key, key, line), @b.set(@matchee, @b.read(d, line), line), Literal.new(false, line)], line), line)
          end

          # A copy of `d` without `keys`.
          def without_keys(d, keys, line)
            copy = @b.temp(:copy)
            deletes = keys.map { |k| @b.send_to(@b.read(copy, line), :delete, [Literal.new(k, line)], line) }
            Seq.new([@b.set(copy, @b.send_to(@b.read(d, line), :dup, [], line), line), *deletes, @b.read(copy, line)], line)
          end

          # A sub-pattern against `value`, kept in its own hidden local so
          # its deconstruct is called once.
          def nested(node, value, line)
            inner = @b.temp(:part)
            Seq.new([@b.set(inner, value, line), pattern(node, inner)], line)
          end

          def conjunction(steps, line)
            steps.reduce { |a, s| And.new(a, s, line) } || Literal.new(true, line)
          end
        end
      end

      include Patterns
    end
  end
end
