# frozen_string_literal: true

module Zr
  # The high-level IR: a tree of Ruby-level nodes, desugared and
  # name-resolved, that every lowering reads instead of Prism. One class
  # per kind; `line` is where the node starts; `locals` lists every local
  # of a scope, parameters first.
  module Hir
    # The slot of a block's implicit `it`. No program can write this name, so
    # `parameters` and `local_variables` leave it out, as CRuby does.
    IT = :"%it"

    # The evals that run a string, with a different self. A program that
    # calls one with an argument compiles ruby at run time, and the
    # string reads the locals of the scope, as `eval` does. The block
    # forms do neither.
    STRING_EVALS = %i[class_eval module_eval instance_eval].freeze

    # The class of every HIR node class below: `Node.new(:a, :b)` makes
    # a Struct class with the fields `a` and `b`, as `Struct.new` does.
    # Each node is thus equal by value, and a walk reads its fields in
    # order with `to_a` and `each_pair`. A node's fields change after it is
    # made (the builder and the lowering set them), so a node is a Struct
    # and not a Data.
    class Node < Struct
    end

    # Whether `value` is a HIR node: one `Node` of the classes below,
    # never a bare `Array`, `Symbol`, `Integer` or other field value.
    def self.node?(value) = value.is_a?(Node)

    # Yields each child of `node`: the fields of a HIR node, or the
    # elements of an Array of nodes. Anything else (nil, a literal value,
    # ...) has no children. Several walks share this fallback for the
    # fields or elements that their own scope-boundary rules do not name;
    # each keeps those rules and only reads its children through this.
    #
    # With no block, returns the children as an Array instead of an
    # Enumerator, so a caller can still write `each_child(node).any? { ... }`
    # without allocating one on every node.
    def self.each_child(node)
      children = case node
                 when Node then node.to_a
                 when Array then node
                 else []
                 end
      block_given? ? children.each { |child| yield child } : children
    end

    # `units` are the files that a require or load reaches, each with its
    # own toplevel, in order of first reference. `warnings` are the
    # parse-time warnings that ruby prints for the file, printed when it
    # runs. `evals` tells that the program links in the compiler.
    # `entries` maps each file path to its unit: an index into `units`,
    # or the entry of a file in eval support.
    # `traced` tells that the program uses TracePoint, so its code fires
    # the events that a TracePoint listens for.
    # `node_ids` maps a HIR node of the main file, by identity, to its prism
    # node id; each Unit has its own.
    # `spots` contains each file's error_highlight spots (Hir::Spots), by
    # the file name in its frames.
    # `activations` is the number of `using` entries in this program. A
    # compile at run time takes the entries after them.
    # `branches` contains each measured file's branch records, by file
    # name, in Coverage's order. `defs` contains each file's def and
    # block spans; a definition uses its span to become a method entry.
    Program = Node.new(:file, :locals, :body, :units, :warnings, :evals, :entries, :traced, :node_ids, :spots,
                       :coverable, :activations, :branches, :defs)
    # `hidden` if the unit loads only for the runtime's own use, as the
    # eval support files do.
    # `source` is the bytes that the unit was built from. `activates`
    # tells that the file took an activation entry for a `using`. The
    # unit cache uses both (lib/zr/unit_cache.rb). It keeps the bytes,
    # not a digest, because the loader also runs in a program with eval,
    # and there it must not require a library that it would then have to
    # load. `node_ids` maps each HIR node of the unit, by identity, to its
    # prism node id.
    Unit = Node.new(:file, :locals, :body, :warnings, :internal, :spots, :hidden, :source, :activates, :node_ids)
    # `require`, `require_relative` or `load` of a literal name: `path`
    # is the resolved file and `unit` is that file's index. Both are nil
    # if no file is found.
    Require = Node.new(:kind, :feature, :path, :unit, :line)

    # The `using` entries of a program, taken before its first line runs,
    # so a compile at run time can take the entries after them. Only a
    # program that links in the compiler needs this, because no other
    # program compiles after it starts.
    Activations = Node.new(:count, :line)

    # A form that this runtime does not support, kept until the program
    # runs it. If the program gets to it, the program stops with a message
    # that gives the form. If not, it costs nothing.
    Stop = Node.new(:what, :line)
    # `autoload :Name, "feature"` on `recv` (nil for self): the file is
    # `path`, unit `unit`; it runs when the constant is first read.
    # `declared` is an autoload of a feature for which a require reads no
    # file. The name is declared and no entry is kept, so nothing waits
    # for a file and `autoload?` returns nil.
    Autoload = Node.new(:recv, :name, :feature, :path, :unit, :line, :declared)
    # A statement list; its value is the last statement's.
    Seq = Node.new(:stmts, :line)
    # A method call. `recv` is nil for an implicit self. `vcall` marks a
    # bare identifier, which is a NameError if no method is found. `opt`
    # marks the operator syntax `recv[i]`, `recv[i] = v` and `recv << v`,
    # which CRuby runs without a frame on its builtin receivers. An
    # argument can be a Splat. `kwargs` is a HashLit passed as keywords,
    # or nil. `block` is a Block literal, a BlockPass, or nil.
    # `using` is the active activation entry at the call, or nil if no
    # refinement is active.
    # `covers` is a safe call's two branches, `[then, else]`, which
    # Coverage counts for a non-nil and a nil receiver. It is nil for all
    # other calls. `interp` marks the `to_s` of an interpolated part under
    # refinements, which a String or a Symbol does not get.
    Send = Node.new(:recv, :name, :args, :line, :vcall, :opt, :block, :kwargs, :safe, :write, :using, :covers, :interp) do
      # `recv.name(args)` at `line`, with keywords for the fields that a
      # send usually leaves at their default. Every field but the first
      # four reads as a boolean somewhere in the lowering (`node.opt &&`,
      # `node.write ?`, ...), so `nil` and `false` mean the same thing;
      # the boolean-shaped ones default `false` here, and the ones that
      # hold a value when present (`block`, `kwargs`, `using`, `covers`)
      # default `nil`.
      def self.of(recv, name, args, line, vcall: false, opt: false, block: nil, kwargs: nil, safe: false, write: nil, using: nil,
                  covers: nil, interp: false)
        new(recv, name, args, line, vcall, opt, block, kwargs, safe, write, using, covers, interp)
      end
    end

    # `using mod`: entry `id` contains the contents of entry `from` plus
    # every refinement in `mod`. `from` is -1 if nothing was active.
    Using = Node.new(:id, :from, :value, :line)
    # Before a statement that contains a `using` that a condition can
    # skip: each `[id, from]` entry contains the contents of entry `from`
    # until its `using` runs.
    UsingDefaults = Node.new(:rows, :line)
    # A value that the lowering already put in record slot `index`. Only
    # the lowering makes this node, for a receiver or argument evaluated
    # once.
    Slot = Node.new(:index, :line)
    # `recv[args] op= value` and `recv.name op= value`, the receiver and
    # arguments evaluated once; `op` is an operator, or :or / :and.
    # `using` is the active refinements, as for a Send, for each of its
    # sends.
    IndexOpAssign = Node.new(:recv, :args, :op, :value, :line, :using)
    # `safe` is `recv&.name op= value`: nil, with nothing else run, if
    # the receiver is nil.
    AttrOpAssign = Node.new(:recv, :name, :op, :value, :line, :safe, :using)
    # `*value` among arguments or elements.
    Splat = Node.new(:value, :line)
    # `**value` among a hash literal's pairs: the key, with a nil value.
    HashSplat = Node.new(:value, :line)
    # `&value`: the block a call passes on.
    BlockPass = Node.new(:value, :line)
    # A block literal: its parameters, every local of its scope
    # (parameters first), and its body.
    Block = Node.new(:params, :locals, :body, :line, :end_line, :cover)
    # `-> (params) { body }`: a Block that is a lambda from the start.
    Lambda = Node.new(:block, :line)
    # The one parameter shape: `required` and `post` are names,
    # `optional` and `keywords` are `[name, default]` pairs (a keyword
    # with no default is required), `rest`, `kwrest` and `block` are a
    # name or nil; a block's `|a, |` has the rest `:implicit`.
    Params = Node.new(:required, :optional, :rest, :post, :keywords, :kwrest, :block) do
      def positional
        required.size + optional.size + post.size
      end

      # Whether a single Array argument spreads over the parameters, as
      # CRuby's block setup decides. A required parameter, or two or more
      # optional ones, cause a spread. A single `|a|` does not, and neither
      # do keywords with exactly one positional and no rest.
      def spread?
        min = required.size + post.size
        keyworded = !keywords.empty? || !kwrest.nil?
        return false if positional == 1 && rest.nil? && (min == 1 || keyworded)

        min.positive? || optional.size > 1
      end

      # Only required parameters: the exact arity that a dispatcher can check.
      def plain?
        optional.empty? && rest.nil? && post.empty? && keywords.empty? && kwrest.nil?
      end

      def names
        positionals = (required + post).flat_map { |r| r.is_a?(MultiTarget) ? r.names : [r] }
        positionals + optional.map(&:first) + [rest].compact + keywords.map(&:first) + [kwrest, block].compact - %i[implicit nokey]
      end

      # `Method#arity`: the required count, or -(count + 1) if the count can
      # vary. A required keyword counts as one argument. Any other keyword
      # form permits one more.
      def arity
        min = required.size + post.size + (keywords.any? { |_, default| default.nil? } ? 1 : 0)
        return -min - 1 if rest && rest != :implicit

        max = required.size + optional.size + post.size + (keywords.any? || (kwrest && kwrest != :nokey) ? 1 : 0)
        min == max ? min : -min - 1
      end

      # `Method#parameters`, in CRuby's order: `[kind, name]` pairs. A
      # destructuring parameter and `it` have no name.
      def rows
        positional = ->(p) { p.is_a?(MultiTarget) || p == IT ? [:req] : [:req, p] }
        [
          *required.map(&positional),
          *optional.map { |name, _| [:opt, name] },
          *(rest && rest != :implicit ? [[:rest, rest]] : []),
          *post.map(&positional),
          *keywords.map { |name, default| [default.nil? ? :keyreq : :key, name] },
          *kwrest_rows,
          *(block ? [[:block, block]] : [])
        ]
      end

      def kwrest_rows
        if kwrest == :nokey then [[:nokey]]
        elsif kwrest then [[:keyrest, kwrest]]
        else []
        end
      end
    end
    Yield = Node.new(:args, :line, :kwargs)
    # `super(args)`; `block` as for a Send. `ZSuper` is the bare `super`,
    # which passes the method's own parameters with their current values.
    # `in_block` marks a bare `super` in a block of a def. CRuby raises for
    # it if `define_method` made the block a method.
    # `using` is the active activation at the super, as for a Send: ruby
    # resolves a super with the refinements of its scope.
    Super = Node.new(:args, :kwargs, :block, :line, :in_block, :using)
    ZSuper = Node.new(:block, :line)
    Break = Node.new(:value, :line)
    Next = Node.new(:value, :line)
    # An Integer, String, Symbol, nil, true or false.
    # `chilled` marks a String literal in a file with no
    # frozen_string_literal: its String warns at its first change.
    Literal = Node.new(:value, :line, :chilled)
    SelfRef = Node.new(:line)
    # `def name(params) body end`; its value is the name. `params` is a
    # Params; `receiver` is the expression of a singleton def
    # (`def self.x`, `def obj.x`), or nil.
    Def = Node.new(:name, :params, :locals, :body, :line, :receiver, :evals, :end_line, :cover)
    # `depth` counts block scopes up to the scope that owns the local.
    Local = Node.new(:name, :depth, :line)
    # A point where a traced program fires a TracePoint `event`: a
    # `:line` event, where ruby's compiler puts one (at a statement that
    # starts a new line).
    Trace = Node.new(:event, :line)
    # Counts one run of branch `id` in a program that Coverage measures.
    # The id is unique in the program, not only in the file: all branches
    # of all files share one counter array, and `Program#branches` tells
    # which records belong to which file. Its value is nil, so it can be
    # anywhere a statement can, also as an else that the source does not
    # have.
    Cover = Node.new(:id, :line)
    Assign = Node.new(:name, :depth, :value, :line)
    # `a, (b, *c), *d, e = value`; its value is the right-hand side's.
    # `taken` is false if the value is not used: a statement before the
    # last of a sequence, or a loop body.
    MultiAssign = Node.new(:target, :value, :line, :taken)
    # The targets before the rest, the rest (a target, `:implicit` for a
    # bare `*`, or nil) and the targets after it. A target is an Assign
    # or IvarWrite with a nil value, a Send with the value to append
    # (`h[k]`, `o.attr`), or a nested MultiTarget. As a block parameter,
    # a MultiTarget is one of the required names.
    MultiTarget = Node.new(:lefts, :rest, :rights, :line, :whole) do
      def names
        (lefts + [rest] + rights).flat_map do |t|
          case t
          when Assign then [t.name]
          when MultiTarget then t.names
          else []
          end
        end
      end
    end
    # `if`. `unless` becomes an If with its branches swapped. A branch can
    # be nil.
    If = Node.new(:cond, :yes, :no, :line)
    # `body_first` is a `begin ... end while cond`: the body runs once
    # before the first test.
    While = Node.new(:cond, :body, :line, :body_first)
    Return = Node.new(:value, :line)
    # `a && b`, `a || b`, `!a`: on truthiness, with short-circuit.
    And = Node.new(:left, :right, :line)
    Or = Node.new(:left, :right, :line)
    Not = Node.new(:value, :line)
    # A class or module that the core defines, read from the runtime and
    # never through lexical scope. A desugaring uses it (`Array` in a
    # pattern), so a program's own `Array` cannot replace it.
    Core = Node.new(:name, :line)
    # A body that runs the first time its site is reached and never again
    # (CRuby's `once` instruction), as `END { }` registers.
    Once = Node.new(:body, :line)
    # `class Name < superclass; body; end`. `scope` is nil for a bare
    # name, `:top` for `::Name`, else the expression before `::`.
    ClassDef = Node.new(:scope, :name, :superclass, :locals, :body, :line, :end_line)
    ModuleDef = Node.new(:scope, :name, :locals, :body, :line, :end_line)
    # `class << target; body; end`: the body runs with the singleton
    # class as self and as the definee.
    SingletonClassDef = Node.new(:target, :locals, :body, :line, :end_line)
    ConstRead = Node.new(:scope, :name, :line)
    ConstWrite = Node.new(:scope, :name, :value, :line)
    IvarRead = Node.new(:name, :line)
    GvarRead = Node.new(:name, :line)
    # `shown` is the name that the program wrote, if it is not `name`.
    GvarWrite = Node.new(:name, :value, :line, :shown)
    CvarRead = Node.new(:name, :line)
    CvarWrite = Node.new(:name, :value, :line)
    # `Name ||= value`: set only if unset or falsy.
    ConstOrWrite = Node.new(:scope, :name, :value, :line)
    # `alias new old`.
    Alias = Node.new(:new_name, :old_name, :line)
    # `alias $new $old`: one global under two names.
    GvarAlias = Node.new(:new_name, :old_name, :line)
    # `undef name, ...`.
    Undef = Node.new(:names, :line)

    # `alias :"#{a}" :"#{b}"` and `undef :"#{a}"`: the names are values.
    AliasValue = Node.new(:new_name, :old_name, :line)

    UndefValue = Node.new(:names, :line)
    # `defined?(...)`: `kind` is the form (:local, :ivar, :gvar, :cvar,
    # :const, :method, :yield, :super, :self, :nil, :true, :false,
    # :assignment, :expression). `target` is the name, the ConstRead, or
    # the Send that the form tests.
    Defined = Node.new(:kind, :target, :line)
    # `case subject; when a, b then body; ... else else_body end`. Each
    # clause is `[values, body]`; a nil subject tests each value itself.
    Case = Node.new(:subject, :clauses, :else_body, :line)
    IvarWrite = Node.new(:name, :value, :line)
    # `[a, b]`. `frozen` if it is the value of a
    # `# shareable_constant_value: literal` constant: built frozen with
    # no send (compile.c freezes it in the compiler).
    ArrayLit = Node.new(:elements, :line, :frozen)
    # The keywords of an array literal made only of double splats, as an
    # Array to splat: `[h]`, or `[]` when they come out empty, so `[**{}]`
    # adds no element (CRuby's pushtoarraykwsplat).
    KwSplatElement = Node.new(:pairs, :line)
    # `{k => v, ...}`: `pairs` is a flat list, key then value. `frozen`
    # as for an ArrayLit.
    HashLit = Node.new(:pairs, :line, :frozen)
    # `$1` and the other numbered groups (`kind` :nth, `number` the
    # group, 0 for `$&`), `` $` `` (:pre), `$'` (:post) and `$+` (:last),
    # read from `$~`'s registers, never through MatchData's methods.
    BackRef = Node.new(:kind, :number, :line)
    # `low..high` / `low...high`. A missing bound is nil. `static` if both
    # ends are Integer or nil literals: one frozen Range for the site.
    RangeLit = Node.new(:low, :high, :exclusive, :line, :static)
    # `"a#{b}c"`: literal and expression parts in order.
    Interp = Node.new(:parts, :line)
    # `/#{x}/o`: the interpolated regexp that its site keeps after the
    # first run.
    RegexpOnce = Node.new(:value, :line)

    # A regexp literal: its source and option bits. One object per site.
    RegexpLit = Node.new(:source, :options, :pinned, :line)
    # `"text".freeze`: the one frozen String of that text, or a send of
    # `freeze` if the program redefines it. `shared` is true for a
    # shareable constant or under a frozen_string_literal comment: the
    # shared String with no send, as the compiler's own fstring. `false`
    # means the same for a text that is not UTF-8: frozen with no send,
    # but not shared.
    FrozenString = Node.new(:value, :line, :shared)
    # `begin body rescue ... else else_body ensure ensure_body end`. The
    # else branch runs after a body that raised nothing. The ensure branch
    # runs on every exit. `rescues` are Rescue nodes in order. `else_body`
    # and `ensure_body` can be nil. A `rescue` modifier is a Begin with
    # one clause and no classes.
    Begin = Node.new(:body, :rescues, :else_body, :ensure_body, :line)
    # One clause: the exception classes (none means StandardError; one
    # can be a Splat), the target that gets the exception (`=> e`, an
    # Assign, IvarWrite or Send target with a nil value) or nil, and the
    # handler.
    Rescue = Node.new(:classes, :target, :body, :line)
    # `retry`: the begin body again, from a rescue clause.
    Retry = Node.new(:line)
    # `redo`: the loop body or block body again, without a new test or
    # new arguments.
    Redo = Node.new(:line)
  end
end
