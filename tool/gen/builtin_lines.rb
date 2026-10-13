# frozen_string_literal: true

require_relative "../gen"

module Zr
  module Dev
    module Commands
      class Gen
        # The lines of CRuby's methods that are written in Ruby, from its
        # builtin sources. TracePoint uses them for :call and :return events,
        # and Method#source_location for the def. The key is `Owner#name`, or
        # `Owner.name` for a singleton method. The value is the
        # `<internal:file>` path, the line of the :call, the last line of the
        # body (where ruby reports the return), the line of the def, and the
        # :line events of the body (Lines) when a call with a block and one
        # without each fire a sequence the build can know, or nil, and the
        # byte columns where the def starts and ends (Method#source_range).
        class BuiltinLines < Generator
          writes "lib/zr/runtime/core/builtin_lines.rb"

          SOURCES = %w[ast dir gc numeric io marshal pack trace_point warning array hash kernel pathname_builtin ractor
                       symbol timev thread_sync nilclass prelude].freeze

          # The :line events that a builtin's body fires, when the build can
          # know them: each statement fires the line it starts on, so the
          # sequence is known when every statement before the last makes no
          # call and has no branch, and the last has no body of its own. A
          # leading `unless defined?(yield)` (or `… unless block_given?`)
          # guard gives a second sequence, for a call without a block.
          module Lines
            module_function

            # The :line events of a call by its shape, or nil when none is known:
            # `block:` for a call with a block, `bare:` for one without, and for a
            # body split on `Primitive.mandatory_only?`, `only:` for a call of
            # `lead:` plain arguments. `raise:` (and `raise_only:` for such a
            # call) is the line of an error that the body raises. `first:` is
            # the line of the body's first statement, where a frame of the
            # method stands as its :call hooks run, also when the rest of its
            # lines are not known.
            def of(node)
              statements = statements_of(node.body)
              return unless statements

              params = parameter_names(node)
              known = {}
              if (split = mandatory_split(statements))
                known[:lead] = node.parameters&.requireds&.size || 0
                only = statements_of(split.statements)
                known[:only] = only && sequence(only)
                known[:raise_only] = raise_line(only, params)
                statements = statements_of(split.subsequent&.statements)
              end
              known.merge!(by_block(statements)) if statements
              known[:first] = statements&.first&.location&.start_line
              known[:raise] = raise_line(statements, params)
              known.compact!
              known unless known.except(:lead).empty?
            end

            # The line of the first statement that gives one of the method's
            # parameters to a Primitive: only such a call raises for what the
            # caller passed. A Primitive in the test of a branch only decides.
            def raise_line(statements, params)
              return if statements.nil? || params.empty?

              statements.each do |statement|
                found = argument_primitives(statement).find { passes?(_1, params) }
                return found.location.start_line if found
              end
              nil
            end

            def parameter_names(node)
              node.parameters&.compact_child_nodes.to_a.flat_map { Array(_1) }.filter_map { _1.name if _1.respond_to?(:name) }
            end

            # The Primitive calls under `node`, but for those in the test of a
            # branch or a loop.
            def argument_primitives(node, found = [])
              found << node if primitive?(node) && !primitive?(node, :attr!) && !primitive?(node, :mandatory_only?)
              test = node.predicate if node.respond_to?(:predicate)
              node.compact_child_nodes.each { argument_primitives(_1, found) unless _1.equal?(test) }
              found
            end

            # Whether a Primitive call reads a parameter: as an argument, or by
            # name in the C of a `cexpr!`.
            def passes?(call, params)
              each_node(call).any? do |n|
                (n.is_a?(Prism::LocalVariableReadNode) && params.include?(n.name)) ||
                  (n.is_a?(Prism::StringNode) && params.any? { |p| n.unescaped.match?(/\b#{p}\b/) })
              end
            end

            # A body's statements without its `Primitive.attr!`, or nil when it is
            # empty or is not a plain list (a `rescue` or an `ensure`).
            def statements_of(body)
              return unless body.is_a?(Prism::StatementsNode)

              statements = body.body.reject { primitive?(_1, :attr!) }
              statements unless statements.empty?
            end

            def mandatory_split(statements)
              first = statements.first
              first if statements.one? && first.is_a?(Prism::IfNode) && primitive?(first.predicate, :mandatory_only?)
            end

            # The lines of a call with a block and of one without.
            def by_block(statements)
              guard = guarded(statements.first)
              if guard.nil?
                lines = sequence(statements)
                return lines ? { block: lines, bare: lines } : {}
              end

              head = statements.first.location.start_line
              rest = statements.drop(1)
              block = rest.empty? ? [head] : sequence(rest)&.then { once([head, *_1]) }
              { block:, bare: once([head, guard.location.start_line]) }.compact
            end

            # The statement that a guard runs when no block comes, or nil.
            def guarded(node)
              return unless node.is_a?(Prism::UnlessNode) && node.else_clause.nil? && block_test?(node.predicate)

              inner = node.statements&.body
              inner.first if inner&.one? && leaf?(inner.first)
            end

            def block_test?(node)
              (node.is_a?(Prism::DefinedNode) && node.value.is_a?(Prism::YieldNode)) ||
                (node.is_a?(Prism::CallNode) && node.receiver.nil? && node.name == :block_given?)
            end

            def sequence(statements)
              *before, last = statements
              return unless before.all? { plain?(_1) } && leaf?(last)

              once(statements.map { _1.location.start_line })
            end

            # Ruby fires one :line for statements that share a line.
            def once(lines) = lines.chunk_while { _1 == _2 }.map(&:first)

            # A statement with no call (but to Primitive), no yield and no branch.
            def plain?(node) = leaf?(node) && each_node(node).none? { call?(_1) }

            # A statement whose own line is the only :line it fires.
            def leaf?(node)
              each_node(node).none? do |n|
                n.is_a?(Prism::StatementsNode) || n.is_a?(Prism::BlockNode) || n.is_a?(Prism::LambdaNode) ||
                  n.is_a?(Prism::IfNode) || n.is_a?(Prism::UnlessNode) || n.is_a?(Prism::CaseNode) ||
                  n.is_a?(Prism::WhileNode) || n.is_a?(Prism::UntilNode) || n.is_a?(Prism::BeginNode) ||
                  n.is_a?(Prism::RescueModifierNode) || n.is_a?(Prism::AndNode) || n.is_a?(Prism::OrNode)
              end
            end

            def call?(node)
              (node.is_a?(Prism::CallNode) && !primitive?(node)) ||
                node.is_a?(Prism::YieldNode) || node.is_a?(Prism::SuperNode) || node.is_a?(Prism::ForwardingSuperNode)
            end

            def primitive?(node, name = nil)
              node.is_a?(Prism::CallNode) && node.receiver.is_a?(Prism::ConstantReadNode) &&
                node.receiver.name == :Primitive && (name.nil? || node.name == name)
            end

            def each_node(node)
              return enum_for(__method__, node) unless block_given?

              yield node
              node.compact_child_nodes.each { each_node(_1) { |n| yield n } }
            end
          end

          # A visitor that finds the defs of one file, with the class and module
          # names around each. It is made on the first call, so that loading
          # this file does not load the prism port (0.25 s).
          def defs_class
            require_relative "../../lib/zr/prism"
            @defs_class ||= Class.new(Prism::Visitor) do
              attr_reader :rows

              def initialize(path)
                super()
                @path = path
                @scope = []
                @singleton = false
                @rows = {}
              end

              def visit_class_node(node) = within(node.constant_path.slice) { super }

              # A def inside `with_jit` applies only when a JIT runs. Without a
              # JIT, the method stays in C.
              def visit_call_node(node)
                super unless node.name == :with_jit && node.receiver.nil?
              end

              def visit_module_node(node) = within(node.constant_path.slice) { super }

              def visit_singleton_class_node(node)
                was = @singleton
                @singleton = node.expression.is_a?(Prism::SelfNode)
                super
              ensure
                @singleton = was
              end

              def visit_def_node(node)
                owner = @scope.join("::")
                owner = "Object" if owner.empty?
                singleton = @singleton || node.receiver.is_a?(Prism::SelfNode)
                key = "#{owner}#{singleton ? "." : "#"}#{node.name}"
                @rows[key] ||= [@path, call_line(node), node.location.end_line, node.location.start_line, Lines.of(node),
                                 [node.location.start_column, node.location.end_column]]
              end

              private

              # The line of the def. For a method split on
              # `Primitive.mandatory_only?`, the line of that test.
              def call_line(node)
                first = node.body.is_a?(Prism::StatementsNode) ? node.body.body.first : nil
                split = first.is_a?(Prism::IfNode) && first.predicate.slice == "Primitive.mandatory_only?"
                split ? first.location.start_line : node.location.start_line
              end

              def within(name)
                @scope.push(name)
                yield
              ensure
                @scope.pop
              end
            end
          end

          def write(io)
            rows = {}
            SOURCES.each do |name|
              defs = defs_class.new("<internal:#{name}>")
              Prism.parse(Dev.cruby("#{name}.rb")).value.accept(defs)
              rows.merge!(defs.rows) { |_key, first, _later| first }
            end

            io.puts "# frozen_string_literal: true"
            io.puts
            io.puts "# Generated by `zr-dev gen builtin_lines` from the pinned ruby's builtin sources. Do not edit."
            io.puts "#"
            io.puts "# Where CRuby's own Ruby methods stand: the path TracePoint names for"
            io.puts "# one, the line its :call reports, the line its :return reports, the"
            io.puts "# line of its def, and the lines its :line events report, with a block"
            io.puts "# and without one, when they come before any call it makes (or nil),"
            io.puts "# and the columns where its def starts and ends."
            io.puts "class TracePoint"
            io.puts "  BUILTIN_LINES = {"
            rows.sort.each { |key, row| io.puts "    #{key.inspect} => #{row.inspect}," }
            io.puts "  }.freeze"
            io.puts "  private_constant :BUILTIN_LINES"
            io.puts "end"
          end
        end
      end
    end
  end
end
