# frozen_string_literal: true

module Ze0
  # Where a local variable lives.
  #
  # `slot` is always a stack slot. `cell` says the slot holds a POINTER to
  # a heap cell rather than the value itself, which is what a name a block
  # captured needs: the cell outlives the frame and every closure over the
  # name shares it. `:owned` is the scope that made the cell and releases
  # it; `:borrowed` is a block reading one out of its `ProcEnv`, whose
  # reference the proc holds. Every read and write goes through `Lower`,
  # which dispatches on this.
  class Local
    attr_reader :slot, :cell

    def initialize(slot, cell)
      @slot = slot
      @cell = cell
    end

    def boxed? = !@cell.nil?
    def owns_cell? = @cell == :owned
  end

  # One `while` or `until` being lowered, and where its two jumps go.
  #
  # `break` leaves through `done` with its value in `result`; `next`
  # returns to `head`, resetting the pool to `mark` first, exactly as the
  # end of an iteration does; `redo` re-enters `body`, which steps
  # nothing. `handling` is the `$!` depth the loop was
  # entered at, so a jump out of a `rescue` clause opened INSIDE the loop
  # pops only the clauses it actually leaves, and `depth` the `ensure`
  # depth, so a jump with a clause to run first travels as a signal.
  #
  # The stack is per SCOPE, which is what makes ruby's rule fall out: a
  # block written inside a loop starts an empty one, so a `break` there is
  # the block's, and a loop written inside a block is found by the block's
  # own `break`.
  class Loop
    attr_reader :head, :done, :result, :mark, :handling, :depth, :body

    def initialize(head, done, result, mark, handling, depth, body)
      @head = head
      @done = done
      @result = result
      @mark = mark
      @handling = handling
      @depth = depth
      @body = body
    end
  end

  # One function being lowered: the CLIF function itself, the bases its
  # code reads, its locals, its `self`, and the blocks every exit path
  # lands in.
  #
  # Scopes nest -- a block body lowers inside the method that wrote it --
  # so `Lower` keeps a stack of these rather than one set of instance
  # variables.
  class Scope
    # `:toplevel` or `:body`; a class body and a block body join them.
    attr_reader :f, :kind
    # The names in scope. The top level holds one table per file -- a
    # required file's top level is its own scope in ruby, so two files may
    # both write `i` and get two slots -- and swaps this as one file's
    # statements give way to the next.
    attr_accessor :locals
    # The `self` of the frame, and the caller's slot a value is answered in.
    attr_accessor :self_operand, :out
    # The call-site block this scope was handed, when it takes one. A
    # method grows the parameter only where it uses a block; everywhere
    # else this is nil and `yield` is refused.
    attr_accessor :blk
    # A block body's `ProcEnv`: what a bare `yield` written inside a block
    # reads the enclosing method's block out of.
    attr_accessor :env
    # `zeo_rodata` and `zeo_syms`, read once per function.
    attr_accessor :rodata, :syms
    # The class or module whose body this is, or whose method: which
    # table a bare call resolves against.
    attr_accessor :owner
    # The class or module whose body this scope is lexically inside, or
    # nil at the top level. `cref` cannot answer it: a reopened builtin
    # has no class row, so its name never joins that chain, and a
    # top-level `def` owns `Object` without opening a body at all.
    attr_accessor :definee
    # The lexical scopes a bare constant searches, innermost first, with
    # `Object` left off the end. Not the owner's name split on `::`: a
    # body written `class A::B::C` searches `C` and then whatever
    # encloses the statement, never `A::B`.
    attr_accessor :cref
    # The shared exits: a raise, a normal finish, and the single block that
    # releases the locals and answers `status`.
    attr_accessor :raise_block, :done_block, :exit_block, :status
    # How many `rescue` clauses this path is inside. `$!` is a stack, so a
    # jump out of one owes a pop per clause it leaves.
    attr_accessor :handling_depth
    # How many `ensure` clauses this path is inside, and how many jumps
    # have travelled as a signal so far. An `ensure` reads the count
    # AFTER its body: only a clause some jump really crossed emits the
    # settle block, so no construct claims a signal that is not its.
    attr_accessor :ensure_depth, :ensure_jumps
    # Whether this body is a lambda, which catches its own `return` and
    # `break` rather than passing either on.
    attr_writer :lambda
    # Where a top-level `return` leaves, and the flag it sets so the
    # file's later runs are skipped: `[label, flag]`.
    attr_accessor :file_return
    # Where a `retry` written in a rescue clause re-enters: the top of
    # the `begin` body, so the whole thing runs again.
    attr_accessor :retry_block
    # Where a `redo` written in a block re-enters: the body, past every
    # binding, because ruby does not re-yield.
    attr_accessor :redo_block
    # Whether this body has a `$~` slot of its own. A match it performs
    # then never reaches the caller's `$1`.
    attr_accessor :svars
    # Whether this body pushed a non-local-return home: a `Signal::Return`
    # aimed HERE folds into its own value at the boundary.
    attr_accessor :catches_return
    # The `while`s this scope is inside, innermost last. `break` and
    # `next` read the last one before they read `kind`.
    attr_reader :loops
    # The `def` this body is, which `super` needs: the class it was
    # WRITTEN in and the parameters a bare `super` forwards. nil in every
    # other kind of scope.
    attr_accessor :definition
    # The class ruby's visibility barrier compares an explicit receiver's
    # method against: the class of `self` where the site is written. A
    # body the runtime installs has none this compile can name, and
    # `dynamic_caller` asks `self` per call instead.
    attr_accessor :caller_class, :dynamic_caller
    # The frame a backtrace prints. `base` is the method or `<main>` a
    # block was written in, and `depth` how many blocks deep it sits, so
    # ruby's "block (2 levels) in Object#run" can be spelled.
    attr_accessor :frame_base, :block_depth

    def initialize(f, kind)
      @f = f
      @kind = kind
      @locals = {}
      # Every table this scope has opened, the scope's own filed under no
      # file. Only the top level opens more.
      @tables = { nil => @locals }
      @block_depth = 0
      @handling_depth = 0
      @ensure_depth = 0
      @ensure_jumps = 0
      @loops = []
      @owner = Names::OBJECT
      # A scope that never asks is `main`, an ordinary Object.
      @caller_class = Names::OBJECT
      @cref = []
    end

    def lambda? = @lambda

    # `file`'s own table of top-level names, opened on first ask.
    def locals_of(file)
      @tables[file] ||= {}
    end

    # Every name this scope holds, which the exit releases.
    def all_locals = @tables.each_value.flat_map(&:values)

    # The label of this scope's own frame.
    def frame_label
      return @frame_base if @block_depth.zero?
      return "block in #{@frame_base}" if @block_depth == 1

      "block (#{@block_depth} levels) in #{@frame_base}"
    end
  end
end
