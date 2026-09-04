# frozen_string_literal: true

module Ze0
  # The `if` conditions a whole-program compile can decide, so a branch
  # that cannot run is never compiled at all.
  #
  # Deciding one matters more than it saves: a `def` in each branch of a
  # guard that stays dynamic leaves TWO definitions of one name and the
  # later one simply wins, so `if RUBY_ENGINE == "truffleruby"` would take
  # the branch written for the engine this is not.
  #
  # The values are the RUNNING ruby's, because ze0 compiled by zeo runs on
  # zeo: a front end targets the runtime it runs on. `RUBY_PLATFORM` is
  # deliberately left out -- a host ruby and zeo name different builds of
  # the same machine, so folding it would make the answer depend on which
  # of them ran the compiler.
  module Guards
    SEEDED = {
      "RUBY_ENGINE" => RUBY_ENGINE,
      "RUBY_VERSION" => RUBY_VERSION,
      "RUBY_ENGINE_VERSION" => RUBY_VERSION,
    }.freeze

    COMPARISONS = %i[== != < <= > >=].freeze

    # true, false, or nil when the condition has to stay.
    def self.static_cond(node)
      case node
      when Prism::TrueNode then true
      when Prism::FalseNode, Prism::NilNode then false
      when Prism::ParenthesesNode then only_statement(node)
      when Prism::AndNode then both(static_cond(node.left), static_cond(node.right), false)
      when Prism::OrNode then both(static_cond(node.left), static_cond(node.right), true)
      when Prism::CallNode then static_call(node)
      end
    end

    def self.only_statement(node)
      body = node.body&.body || []
      static_cond(body.first) if body.size == 1
    end

    # `a && b` and `a || b`, three-valued. One decided side can settle the
    # whole guard even when the other stays unknown: `x && false` is falsy
    # for either x, and `x || true` truthy the same way.
    def self.both(left, right, stop)
      return stop if left == stop || right == stop
      return right if left == !stop

      nil
    end

    def self.static_call(node)
      args = node.arguments&.arguments || []
      return negated(node) if node.name == :! && args.empty?
      return nil unless COMPARISONS.include?(node.name) && args.size == 1

      left = guard_string(node.receiver)
      right = guard_string(args.first)
      left && right && left.public_send(node.name, right)
    end

    def self.negated(node)
      inner = static_cond(node.receiver)
      inner.nil? ? nil : !inner
    end

    # One side of a comparison, as the String ruby would compare. Only a
    # literal and the seeded constants are facts a compile can read.
    def self.guard_string(node)
      case node
      when Prism::StringNode then node.unescaped
      when Prism::ConstantReadNode then SEEDED[node.name.to_s]
      end
    end
  end
end
