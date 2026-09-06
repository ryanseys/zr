# frozen_string_literal: true

module Ze0
  # A parameter list, read off a Prism node once and asked about after.
  #
  # The order of the fields is the SLOT order the runtime's binder uses:
  # required, optional, a named rest, post, keywords in declared order, a
  # named kwrest. An anonymous `*` or `**` takes no slot -- nothing can
  # name it -- and the block is a channel of its own, never a slot.
  class Params
    attr_reader :required, :optional, :rest, :post, :keywords, :kwrest, :block, :no_keywords
    # The `(a, b)` parameters, by the slot name each was given. ruby
    # reports one with no name at all, so it needs a name here that no
    # source can write and `rows` emits the empty one.
    attr_reader :destructures

    def initialize(required, optional, rest, post, keywords, kwrest, block, no_keywords,
                   destructures = {})
      @required = required
      @optional = optional
      @rest = rest
      @post = post
      @keywords = keywords
      @kwrest = kwrest
      @block = block
      @no_keywords = no_keywords
      @destructures = destructures
    end

    # The names the slots hold, in slot order.
    def slot_names
      required +
        optional.map(&:name) +
        (rest&.named? ? [rest.name] : []) +
        post +
        keywords.map(&:name) +
        (kwrest&.named? ? [kwrest.name] : [])
    end

    # Which slots the binder may leave unbound, so the body runs their
    # default instead. Only an optional positional and an optional keyword
    # can be absent.
    def optional_slots
      first = required.size
      positional = (first...first + optional.size).to_a
      at = first + optional.size + (rest&.named? ? 1 : 0) + post.size
      keyword = keywords.each_with_index.reject { |k, _| k.required }.map { |_, i| at + i }
      positional + keyword
    end

    # The default expression of each optional slot, by slot index.
    def defaults
      first = required.size
      rows = optional.each_with_index.map { |o, i| [first + i, o.default] }
      at = first + optional.size + (rest&.named? ? 1 : 0) + post.size
      rows + keywords.each_with_index.reject { |k, _| k.required }
                     .map { |k, i| [at + i, k.default] }
    end

    # Required positionals and nothing else: the shape whose trampoline
    # needs no binder, only a count check.
    def plain?
      optional.empty? && rest.nil? && post.empty? && keywords.empty? &&
        kwrest.nil? && !no_keywords && block.nil?
    end

    # `(kind, name)` per parameter in ruby's `Method#parameters` order,
    # which is the sidecar's reflection row.
    def rows
      required.map { |n| ["req", named(n)] } +
        optional.map { |o| ["opt", o.name] } +
        (rest&.named? ? [["rest", rest.name]] : []) +
        post.map { |n| ["req", named(n)] } +
        keywords.map { |k| [k.required ? "keyreq" : "key", k.name] } +
        (kwrest&.named? ? [["keyrest", kwrest.name]] : []) +
        (block ? [["block", block]] : [])
    end

    # A destructuring parameter has no name in ruby's own report.
    def named(slot) = destructures.key?(slot) ? "" : slot

    # Whether the callee is handed the caller's block as a parameter.
    def takes_block?(uses_yield)
      uses_yield || !block.nil?
    end

    # One optional positional: its name and the expression its default is.
    class Optional
      attr_reader :name, :default

      def initialize(name, default)
        @name = name
        @default = default
      end
    end

    # One keyword: its name, its default (nil when required), and which.
    class Keyword
      attr_reader :name, :default, :required

      def initialize(name, default, required)
        @name = name
        @default = default
        @required = required
      end
    end

    # A `*`/`**` that binds nothing (`PARAM_STAR_ANON`) still changes what
    # the binder accepts, so it is recorded with no name.
    #
    # An IMPLICIT star is the trailing comma of `|a, |`. It destructures and
    # drops like an anonymous one, but it is not in the signature: it never
    # reaches `arity`, and a lambda -- which does not destructure at all --
    # is as strict as it would be without the comma.
    class Star
      attr_reader :name

      def initialize(name, implicit: false)
        @name = name
        @implicit = implicit
      end

      def named? = !@name.nil?
      def implicit? = @implicit
    end
  end
end
