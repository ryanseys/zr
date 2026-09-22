# frozen_string_literal: true

require_relative "../ir"
require_relative "../machine/description"
require_relative "scope"
require_relative "function/expressions"
require_relative "function/definitions"
require_relative "function/sends"
require_relative "function/control"
require_relative "function/regions"
require_relative "function/params"
require_relative "function/targets"
require_relative "function/defined"
require_relative "function/tracing"
require_relative "function/inline"
require_relative "function/iterators"

module Ze0
  module Zr
    # One IR function for one Ruby scope: the toplevel (`kind` :main, no
    # parameters), a method (:def, the method ABI), a class or module body
    # (:class or :module, taking the class and the cref) or a block
    # (:block, taking its Proc, the arguments and a block).
    #
    # Every function keeps a frame record in its frame: its locals, and
    # the slots a send fills with its receiver and arguments while the
    # next argument is evaluated, so the collector sees every Value the
    # function holds across a call. The record names its FrameMeta and
    # carries the current line, for backtraces. A call answering `undef`
    # means a signal is pending: the function leaves through its landing
    # block, answering `undef` itself.
    #
    # A scope that holds a block keeps its locals in an Env cell, kept in
    # the record's first slot, so the block reads and writes them there; a
    # block reaches outer locals through its Proc's env chain.
    class Function
      include Expressions
      include Definitions
      include Sends
      include Control
      include Regions
      include Params
      include Targets
      include Defined
      include Tracing
      include Inline
      include Iterators

      KINDS = { main: "KIND_MAIN", top: "KIND_TOP", def: "KIND_DEF", class: "KIND_CLASS", module: "KIND_MODULE", sclass: "KIND_SCLASS", block: "KIND_BLOCK", eval: "KIND_EVAL" }.freeze
      # The most arguments a direct entry takes in registers; `direct0`
      # to `direct4` are its ABIs, one a count (rt/kernel/class.rb).
      DIRECT_ARGS = 4
      ABI = { main: [], top: [], def: %w[i64 i64 i64 i64 i64 i64], class: %w[i64 i64], module: %w[i64 i64], sclass: %w[i64 i64], block: %w[i64 i64 i64 i64], eval: %w[i64 i64 i64 i64],
              **(0..DIRECT_ARGS).to_h { |n| [:"direct#{n}", %w[i64] * (4 + n)] } }.freeze
      def self.direct_abi(n) = :"direct#{n}"

      # The `&b` parameter bound as the block it was given, a Proc still
      # on the caller's stack, or nil (`Params#raw_block?`).
      attr_reader :meta, :outer, :kind, :raw_block

      # The Def, Block or body node this function came from.
      def def_node
        @def
      end

      # Whether a def takes the direct ABI (`ABI[:direct]`): required
      # positionals alone, four at most, none a pattern, so a site that
      # hands it that many arguments proves its count and it reads them
      # out of registers with no keyword word and no count to check
      # (rt/kernel/class.rb, MEntry.direct). A traced program's defs keep
      # the generic ABI, since its hooks read every frame the same way.
      def self.direct_def?(node, lower)
        p = node.params
        !lower.traced? && p.plain? && p.required.size <= DIRECT_ARGS && p.required.none?(Hir::MultiTarget)
      end

      def initialize(lower, name, locals, body, node, kind, outer: nil)
        @l = lower
        @name = name
        @locals = locals
        @body = body
        @def = node
        @kind = kind
        @direct = kind == :def && Function.direct_def?(node, lower)
        @outer = outer
        @frame = lower.layout("Frame")
        @task = lower.layout("Task")
        @cref_layout = lower.layout("RCref")
        @proc_layout = lower.layout("RProc")
        @env_layout = lower.layout("REnv")
        @slot_of = locals.each_with_index.to_h
        lower.spell(locals)
        # The locals this scope reaches outside itself: each one's depth
        # from here, in the order they are first reached, and the ones it
        # writes.
        @captures = {}
        @writes = []
        # A traced program's hooks read a Binding of any frame, which
        # only an Env gives.
        @has_env = %i[eval main].include?(@kind) || Scope.holds_block?(body) || Scope.opens_locals?(body) ||
                   default_expressions.any? { |d| Scope.holds_block?(d) || Scope.opens_locals?(d) } ||
                   (lower.traced? && !lower.internal? && %i[def block top].include?(@kind))
        @raw_block = raw_block?(node.params) ? node.params.block : nil if %i[def block].include?(@kind)
        @sites = 0
        @loops = []
        @regions = []
        @retries = []
      end

      def lower
        @f = IR::Function.new(@name, ABI.fetch(@direct ? Function.direct_abi(@def.params.required.size) : @kind), "i64")
        enter
        bind_params
        # A method that only recurses has no back edge: its entry is
        # where it hands the turn on, once its record holds its arguments.
        preempt if @kind == :def
        trace_open
        cover_method if @kind == :def && method_cover
        if @kind == :block
          @body_label = @f.label
          @f.jump(@body_label)
          switch(@body_label)
        end
        last = expr(@body)
        leave(last) unless @f.terminated?
        land if @landing
        # Now the body is lowered, what it reaches outside itself is
        # known, and the table its meta names can be written.
        @l.captures_table(@name, capture_rows)
        @l.functions << @f
        @f
      end

      # The def-site row this scope claims when it makes a method, or
      # nil where the program measures none. A block carries one too:
      # `define_method` makes a method of one, and ruby locates that
      # method at the block.
      def method_cover = %i[def block].include?(@kind) ? @def&.cover : nil

      # The record slot of the local `node` names, `node.depth` scopes up.
      def slot_at(node)
        scope_at(node.depth).slot_index(node)
      end

      # A def's entry, block and found node, where its ABI puts them.
      def arg_entry = @f.args[@direct ? 1 : 3]
      def arg_blk = @f.args[@direct ? 2 : 4]
      def arg_found = @f.args[@direct ? 3 : 5]

      # The function `depth` block scopes out from this one.
      def scope_at(depth)
        fn = self
        # A block body run in place (`Iterators`): its own scope stands
        # first, and this one is a level out.
        if @inline_scope
          return @inline_scope if depth.zero?

          depth -= 1
        end
        depth.times { fn = fn.outer }
        fn
      end

      # The data object the meta emitted for this scope's local names.
      def locals_table = "zr_locals_#{@name}"

      def slot_index(node)
        @slot_of.fetch(node.name) { @l.refuse(node, "#{node.name} is not a local of this scope") }
      end

      private

      # The prologue: the stack check, then link the record into the
      # task's chain, fill its header, nil the slots, and make the Env
      # when a block needs one.
      # The program's toplevel names its file to the runtime for `$0`.
      def program_start
        file = @f.symbol_value(@f.symbol(@l.file_bytes))
        kernel("zr_program_start", file, imm(@l.file.bytesize))
      end

      # The file's parse-time warnings, on stderr as the file starts.
      def parse_warnings
        @l.warnings.each do |line|
          text = "#{line}\n"
          kernel("zr_write_err", @f.symbol_value(@f.symbol(@l.literal(text))), imm(text.bytesize))
        end
      end

      # A core def opens with its `Primitive.attr!` rows: `:hidden` on a
      # helper CRuby has no method for, which leaves no backtrace row, and
      # `:ruby` on a method CRuby itself writes in Ruby, which answers its
      # own parameters as CRuby's does.
      def attributes
        return [] unless @l.internal? && @kind == :def

        @attributes ||= begin
          # A def with a `rescue` or `ensure` opens its protected body.
          body = @body.is_a?(Hir::Begin) ? @body.body : @body
          stmts = body.is_a?(Hir::Seq) ? body.stmts : [body]
          stmts.take_while { |stmt| attribute_row?(stmt) }.map { |stmt| stmt.args.first.value }
        end
      end

      def attribute_row?(node)
        node.is_a?(Hir::Send) && node.name == :attr! && node.recv.is_a?(Hir::ConstRead) && node.recv.name == :Primitive &&
          node.args.first.is_a?(Hir::Literal)
      end

      def hidden_def? = attributes.include?(:hidden)

      # The name an instance variable `name` is kept under. The runtime's
      # own, the core library's and the native halves', are hidden, named
      # without their `@` as CRuby names the fields its C keeps, so a
      # program sees none of them; a def marked `:ivars` keeps the ones
      # CRuby writes in Ruby, and so do prism's and openssl's ports
      # (VISIBLE_IVARS).
      def ivar_name(name)
        return name unless @l.internal?
        return name if Hir::Build::VISIBLE_IVARS.include?(@l.file)

        fn = self
        fn = fn.outer while fn.kind == :block && fn.outer
        fn.send(:attributes).include?(:ivars) ? name : name.to_s.delete_prefix("@").to_sym
      end

      def enter
        @base = if stack_env? then 1 + @locals.size
                elsif @has_env then 1
                else @locals.size
                end
        @nvalues = @base + [Scope.staging(@body), *default_expressions.map { |e| Scope.staging(e) }].max + prologue_slots
        @sp = @base
        @record = @f.slot(@frame.size + (8 * @nvalues))
        @rec = @f.stack_addr(@record)
        @task_addr = @f.fetch("i64", static("current_task"), 0)
        # A method is called with its own entry and the chain node it
        # was found on (`Machine.sig :method`): its name and cref come
        # off the entry, and both go into the record before the stack
        # check so that nothing holds them across it.
        if @kind == :def
          @f.store(arg_entry, @rec, off(@frame, "entry"))
          @f.store(arg_found, @rec, off(@frame, "defined"))
          cref = entry_field("cref")
        end
        stack_check
        @prev = @f.fetch("i64", @task_addr, off(@task, "top"))
        @f.store(@prev, @rec, off(@frame, "prev"))
        line = @def ? @def.line : 1
        name = @def && %i[class module].include?(@kind) ? @def.name : 0
        params = @def.params if %i[def block].include?(@kind)
        kind = hidden_def? ? "KIND_HIDDEN" : @l.frame_kind(@kind)
        node_id = @def ? @l.node_id(@def) : 0
        @meta = @l.meta(@name, kind, line, name, @outer&.meta, params, @locals, @has_env, attributes.include?(:ruby),
                        captures: true, node: node_id, cover: method_cover)
        @f.store(@f.symbol_value(@f.symbol(@meta)), @rec, off(@frame, "meta"))
        @line = line | (node_id << 32)
        @f.store(imm(@line), @rec, off(@frame, "line"))
        @proc = @f.args[0] if @kind == :block
        @qnil = imm(@l.const("QNIL"))
        @self = case @kind
                when :main, :top then global("G_MAIN")
                when :block then proc_field("self")
                else @f.args[0]
                end
        @cref = case @kind
                when :main, :top then global("G_TOP_CREF")
                when :def then cref
                when :block then proc_field("cref")
                else @f.args[1]
                end
        # An eval's block is the one the scope it runs in was given, so a
        # `yield` in the string reaches the caller's block.
        @blk = case @kind
               when :def then arg_blk
               when :block then proc_field("blk")
               when :eval then @f.args[3]
               else @qnil
               end
        @f.store(@self, @rec, off(@frame, "self"))
        @f.store(@cref, @rec, off(@frame, "cref"))
        @f.store(@blk, @rec, off(@frame, "blk"))
        # A block's frame keeps the block its call was given in `defined`
        # (a def's keeps the node it was found on): a `define_method`
        # body finds the block a `break` leaves through there.
        unless @kind == :def
          @f.store(imm(0), @rec, off(@frame, "entry"))
          @f.store(@kind == :block ? @f.args[3] : @qnil, @rec, off(@frame, "defined"))
        end
        # The serial is given when something first needs one
        # (`zr_frame_serial`); `$~` and `$_` are made when first written.
        @f.store(imm(0), @rec, off(@frame, "serial"))
        @f.store(imm(@nvalues), @rec, off(@frame, "nvalues"))
        @f.store(@qnil, @rec, off(@frame, "svars"))
        # A refinement in use belongs to the call site, not to what the
        # site called: a ruby frame of its own starts with none.
        @f.store(@qnil, @task_addr, off(@task, "refine"), region: :task)
        program_start if @kind == :main && !@l.internal?
        parse_warnings if %i[main top eval].include?(@kind) && !@l.internal?
        # A required parameter's slot takes the argument straight from
        # argv once the arity is checked (`bind_method`), with nothing
        # that can collect in between: it needs no nil first.
        skip = direct_params.map { |name| slot_of(name) }
        (0...@nvalues).each { |i| @f.store(@qnil, @rec, value_offset(i)) unless skip.include?(i) }
        @f.store(@rec, @task_addr, off(@task, "top"))
        return unless @has_env

        parent = @kind == :block ? proc_field("env") : @qnil
        @env = if @kind == :eval then @f.args[2]
               elsif stack_env? then env_image(parent)
               else kernel("zr_env_new", parent, imm(@locals.size), @f.symbol_value(@f.symbol(locals_table)))
               end
        @f.store(@env, @rec, value_offset(0))
        kernel("zr_toplevel_binding", @env, @self, @cref, @f.symbol_value(@f.symbol(@meta))) if @kind == :main && !@l.internal?
      end

      # A method's or a block's Env starts in its record: an REnv image
      # whose slots are the record's own local slots (1 up to the count),
      # flagged a stack's and marked already, so the collector reads
      # nothing through it. The first keeper of the scope moves it to a
      # cell (`zr_env_escape`, rt/kernel/proc.rb) and points the image's
      # `slots` at the cell's, which every read and write loads first.
      def stack_env? = @has_env && %i[def block].include?(@kind)

      def env_image(parent)
        env = @f.stack_addr(@f.slot(@env_layout.size))
        basic = @l.layout("RBasic")
        @f.store(imm(%w[T_ENV FL_ALLOCATED FL_STACK].sum { |c| @l.const(c) }), env, off(basic, "flags"))
        @f.store(@qnil, env, off(basic, "klass"))
        fields = {
          "parent" => parent, "slots" => @f.iadd(@rec, imm(value_offset(1))), "nslots" => imm(@locals.size),
          "names" => @f.symbol_value(@f.symbol(locals_table)), "cell" => @qnil, "home" => @rec
        }
        fields.each { |name, v| @f.store(v, env, off(@env_layout, name)) }
        env
      end

      # SystemStackError when the record would sit below the task's stack
      # limit; nothing is linked yet, so the answer leaves at once.
      def stack_check
        limit = @f.fetch("i64", @task_addr, off(@task, "stack_limit"))
        over = @f.label
        ok = @f.label
        @f.brif(@f.icmp("ult", @rec, limit), over, ok)
        switch(over)
        @f.ret(kernel("zr_stack_overflow"))
        switch(ok)
      end

      # The landing block: a pending signal leaves the function, unless
      # it is a `return` from a block of this method, whose value is ours.
      def land
        switch(@landing, open: true)
        # A block frame catches one too: a signal whose home is this very
        # frame belongs to it, which happens when the block is a lambda
        # and a block inside it returned.
        if %i[def main top eval block].include?(@kind) && @has_env
          take(kernel("zr_catch_return", @rec))
        end
        take(kernel("zr_catch_return_here")) if @kind == :def && @def&.evals
        leave(qundef, unwinding: true)
      end

      # The value a landing block answers when the catch it just ran
      # took the signal; otherwise the block goes on.
      def take(caught)
        done = @f.label
        none = @f.label
        @f.brif(@f.icmp("eq", caught, qundef), none, done)
        switch(done)
        leave(caught)
        switch(none)
      end

      # A parameter's default runs in the prologue, staging like the body.
      def default_expressions
        return [] unless %i[def block].include?(@kind)

        p = @def.params
        p.optional.map(&:last) + p.keywords.map(&:last).compact
      end

      # The record slots the prologue keeps for itself: one for a
      # method's keyword Hash, one for the Array a block spreads over its
      # parameters, and one per level of a destructuring parameter.
      def prologue_slots
        return 0 unless %i[def block].include?(@kind)

        p = @def.params
        nested = (p.required + p.post).grep(Hir::MultiTarget).map { |t| Scope.targets(t) }.max || 0
        spread = @kind == :block && p.spread? ? 1 : 0
        (keywords?(p) ? 1 : 0) + spread + nested
      end

      # The scope leaves with `value`, firing its closing event first
      # unless it never opened: an arity error leaves before the event.
      def leave(value, unwinding: false, opened: true, line: nil)
        value = trace_close(value, unwinding, line) if opened
        @f.store(@prev, @task_addr, off(@task, "top"), region: :task)
        @f.ret(value)
      end

      # A call's answer, after the test for a pending signal: `undef`
      # takes the landing block.
      def checked(value)
        go = @f.label
        @f.brif(@f.icmp("eq", value, qundef), landing, go)
        switch(go)
        value
      end

      # Continue in `block`. The line the record carries is unknown
      # again, since more than one path may arrive.
      def switch(block, open: false)
        @f.switch(block, open: open)
        @line = nil
      end

      # The line a backtrace reports for what runs next.
      def at_line(line, node_id = 0)
        # An inlined body's lines are its def's, and nothing in a copy
        # raises or polls: the record keeps the caller's line.
        return if @inlining

        word = line | (node_id << 32)
        return if word == @line

        @line = word
        @f.store(imm(word), @line_rec || @rec, off(@frame, "line"))
      end

      # The same for `node`, with the id of the prism node it came from in
      # the word's high half, which node_id_for_backtrace_location reads.
      def at_node(node)
        at_line(node.line, @l.node_id(node))
      end

      # The address of the kernel's static word `name`, found once per
      # function.
      def static(name)
        @f.symbol_addr(@f.symbol("zr_static_#{name}"))
      end

      # The address of a fresh cell for one site's cache: `count` of the
      # kernel's `layout` (rt/kernel/cache.rb).
      def cache(prefix, layout, count = 1)
        @f.symbol_value(@f.symbol(@l.cache_cell(prefix, @l.layout(layout).size * count)))
      end

      # The same for the site `node`, one cell however many times the
      # node is lowered: its def's function and every copy inlined at a
      # call site (`Inline`) share it.
      def site_cache(node, prefix, layout, count = 1)
        @f.symbol_value(@f.symbol(@l.site_cell(node, prefix, @l.layout(layout).size * count)))
      end

      # `@name` and `@name = v` at their sites: the row of self's table
      # the site's cell `ic` guesses, answered in a block of its own when
      # the guess holds `id`, else the branch to `slow`, the kernel's
      # read or write, which sets the guess (rt/kernel/cache.rb). The
      # inline path takes a plain object, class or module read outside
      # a ractor (a ractor's isolation rule is the kernel's), not frozen
      # when `writing`.
      def guessed_ivar_row(ic, ivar, slow, writing:)
        table = @l.layout("IvTab")
        entry = @l.layout("IvEntry")
        plain = @f.label
        indexed = @f.label
        hit = @f.label
        pointer = @f.band(@f.icmp("eq", @f.band(@self, imm(7)), imm(0)), @f.icmp("ugt", @self, @qnil))
        outside = @f.icmp("eq", @f.fetch("i64", @task_addr, off(@task, "ractor")), imm(0))
        @f.brif(@f.band(pointer, outside), plain, slow)
        switch(plain)
        t = own_ivar_table(slow, writing)
        i = @f.fetch("i64", ic, off(@l.layout("IvarCache"), "index"))
        len = @f.fetch("i64", t, off(table, "len"))
        if block_given?
          # A write whose guess is the row past the last of a plain
          # object's table, with a row to spare: the first assignment in
          # an `initialize`, which the block appends when the table's
          # names answer that no row holds the name (a site shared by two
          # classes may guess past the end of a table that holds it).
          past = @f.label
          room = @f.label
          append = @f.label
          @f.brif(@f.icmp("ult", i, len), indexed, past)
          switch(past)
          in_cell = @f.icmp("eq", t, @f.iadd(@self, imm(off(@l.layout("RObject"), "iv"))))
          @f.brif(@f.band(@f.icmp("eq", i, len), in_cell), room, slow)
          switch(room)
          spare = @f.icmp("ult", len, @f.fetch("i64", t, off(table, "cap")))
          unnamed = @f.icmp("eq", @f.band(@f.fetch("i64", t, off(table, "names")), sym_bit(ivar)), imm(0))
          @f.brif(@f.band(spare, unnamed), append, slow)
          switch(append)
          yield t, len
        else
          @f.brif(@f.icmp("ult", i, len), indexed, slow)
        end
        switch(indexed)
        row = @f.iadd(@f.fetch("i64", t, off(table, "rows")), @f.ishl(i, imm(Math.log2(entry.size).to_i)))
        @f.brif(@f.icmp("eq", @f.fetch("i64", row, off(entry, "id")), sym_word(ivar)), hit, slow)
        switch(hit)
        row
      end

      # The collector's write barrier, where a site has stored `v` into
      # `owner` without going through the kernel: a row of self's ivar
      # table, or an element of an Array.
      #
      # A minor collection starts from the roots and from what the barrier
      # remembered, and stops at every object it finds already marked, so
      # an old object that has come to hold a young one must be written
      # down or the young one is swept from under it.
      #
      # What is emitted here is the cheap half of `zr_write_barrier`: self
      # old, and `v` a cell rather than an immediate. The kernel's own
      # does the rest and is reached only where both hold, which a store
      # of a Fixnum, of nil, of true or false or of a Symbol never does.
      #
      # `owner` is a cell in an arena, so its age bit is where its
      # address says it is: self for an ivar, which is a plain object, a
      # class or a module -- `own_ivar_table` sent every other kind to
      # the kernel, and a Proc or an Env on the machine stack with it --
      # and the receiver for an element, which the site has already found
      # to be an Array.
      def cell_barrier(owner, v)
        return if immediate?(v)

        head = @l.layout("ArenaHead")
        marks = @l.const("MARK_BYTES")
        arena = @f.band(owner, imm(~(@l.const("ARENA_BYTES") - 1)))
        first = @f.iadd(arena, imm(@l.const("ARENA_HEAD") + (marks * @l.const("ARENA_MAPS"))))
        index = @f.ushr(@f.isub(owner, first), @f.fetch("i64", arena, off(head, "shift")))
        at = @f.iadd(@f.iadd(arena, imm(@l.const("ARENA_HEAD") + marks)), @f.ishl(@f.ushr(index, imm(6)), imm(3)))
        aged = @f.icmp("ne", @f.band(@f.fetch("i64", at, 0), @f.ishl(imm(1), @f.band(index, imm(63)))), imm(0))
        cell = @f.band(@f.icmp("eq", @f.band(v, imm(7)), imm(0)), @f.icmp("ugt", v, @qnil))
        remember = @f.label
        done = @f.label
        @f.brif(@f.band(aged, cell), remember, done)
        switch(remember)
        kernel("zr_write_barrier", owner, v)
        @f.jump(done)
        switch(done)
      end

      def ivar_barrier(v) = cell_barrier(@self, v)

      # Whether the compiler already knows `v` is an immediate, and so
      # knows the barrier's own test fails. Most of what a program
      # stores into a local, an ivar or an Array is a literal, and every
      # literal reaches `imm`: a Fixnum, a flonum, a Symbol, nil, true
      # and false.
      def immediate?(v)
        word = @f.iconst_of(v)
        !word.nil? && @l.immediate?(word)
      end

      # The ivar table self keeps as its own: in its cell for a plain
      # object, in its extension for a class or module; `slow` for any
      # other kind, or a frozen one when `writing`.
      def own_ivar_table(slow, writing)
        object = @f.label
        other = @f.label
        classy = @f.label
        found, (t,) = @f.block(["i64"])
        mask = @l.const("T_MASK") | (writing ? @l.const("FL_FREEZE") : 0)
        kind = @f.band(@f.fetch("i64", @self, off(@l.layout("RBasic"), "flags")), imm(mask))
        @f.brif(@f.icmp("eq", kind, imm(@l.const("T_OBJECT"))), object, other)
        switch(object)
        @f.jump(found, [@f.iadd(@self, imm(off(@l.layout("RObject"), "iv")))])
        switch(other)
        @f.brif(@f.bor(@f.icmp("eq", kind, imm(@l.const("T_CLASS"))), @f.icmp("eq", kind, imm(@l.const("T_MODULE")))), classy, slow)
        switch(classy)
        ext = @f.fetch("i64", @self, off(@l.layout("RClass"), "ext"))
        @f.jump(found, [@f.iadd(ext, imm(off(@l.layout("ClassExt"), "iv")))])
        switch(found)
        t
      end

      # The Env `depth` scopes up: this scope's own, or the Proc's chain,
      # walked inline, a parent a load.
      def env_at(depth)
        env, up = @has_env ? [@env, depth] : [proc_field("env"), depth - 1]
        up.times { env = @f.fetch("i64", env, off(@env_layout, "parent")) }
        env
      end

      # Slot `i` of the Env `depth` scopes up: a load of the slots and a
      # load or store at the slot, inline, since every local of a scope
      # that holds a block lives there (rt/kernel/proc.rb).
      def env_slot(i, depth)
        [@f.fetch("i64", env_at(depth), off(@env_layout, "slots")), 8 * i]
      end

      def read_local(i, depth, name = nil)
        if @inline_scope
          return @f.fetch("i64", @rec, value_offset(i)) if depth.zero?

          depth -= 1
        end
        capture(name, depth, write: false)
        return @f.fetch("i64", @rec, value_offset(i)) if depth.zero? && !@has_env

        @f.fetch("i64", *env_slot(i, depth))
      end

      def write_local(i, depth, v, name = nil)
        if @inline_scope
          if depth.zero?
            @f.store(v, @rec, value_offset(i))
            return v
          end
          depth -= 1
        end
        capture(name, depth, write: true)
        if depth.zero? && !@has_env
          @f.store(v, @rec, value_offset(i))
        else
          env = env_at(depth)
          @f.store(v, @f.fetch("i64", env, off(@env_layout, "slots")), 8 * i)
          env_barrier(env, v)
        end
        v
      end

      # The collector's write barrier where a scope has written an outer
      # local. An Env that has escaped to the heap outlives the frame
      # that made it, so a store into its slots is a store into a cell
      # like any other; one still on the machine stack has its slots in
      # the frame, which every collection reads as a root, and the
      # kernel's barrier steps over it by its FL_STACK.
      #
      # The barrier is `zr_env_barrier` and not `zr_write_barrier`,
      # because `env` here is the frame's image wherever the scope has
      # one, and after the scope escapes that image's slots are the
      # cell's. The cell is what the barrier has to be handed.
      #
      # The test emitted here is that `v` is a cell rather than an
      # immediate, which a store of a Fixnum, of nil, of true or false or
      # of a Symbol fails; the kernel's own does the rest.
      def env_barrier(env, v)
        return if immediate?(v)

        remember = @f.label
        done = @f.label
        @f.brif(@f.band(@f.icmp("eq", @f.band(v, imm(7)), imm(0)), @f.icmp("ugt", v, @qnil)), remember, done)
        switch(remember)
        kernel("zr_env_barrier", env, v)
        @f.jump(done)
        switch(done)
      end

      # A local this scope reads or writes in a scope outside itself. A
      # Ractor refuses a block that reaches one and names it, so every
      # scope between the two records it: a block reaches past the block
      # that holds it.
      def capture(name, depth, write:)
        return if name.nil? || depth.zero?

        @captures[name] ||= depth
        @writes << name if write && !@writes.include?(name)
        @outer&.__send__(:capture, name, depth - 1, write: write)
      end

      # `[name, written, rebound]` for each local this scope reaches
      # outside itself: whether it writes the local, and whether the scope
      # that owns the local binds it more than once. `Ractor.shareable_proc`
      # refuses a block for either.
      def capture_rows
        @captures.map do |name, depth|
          home = self
          depth.times { home = home.outer }
          [name, @writes.include?(name), home.bindings[name] > 1]
        end
      end

      # How many times each local of this scope is bound: once for a
      # parameter, and once for every assignment to it here or in a block
      # inside, wherever it runs and however often. That is how ruby counts
      # a local that "may be reassigned": `x = 1` in a loop is one binding,
      # `x = 1; x = 2` is two.
      def bindings
        @bindings ||= begin
          counts = Scope.assignments(@body)
          params = %i[def block].include?(@kind) ? @def.params : nil
          params&.names&.each { |name| counts[name] += 1 }
          counts
        end
      end
      protected :bindings

      # `nodes` evaluated into fresh record slots, `extra` more reserved
      # after them; the block gets the address of the first slot and its
      # index, and the slots are free again after it.
      # `evaluate` lowers a node where `expr` is not what this caller
      # wants: string interpolation takes its literal pieces as shared
      # frozen Strings, since it hands none of them to the program.
      def staged(nodes, extra = 0, evaluate: nil)
        base = reserve(nodes.size + extra)
        nodes.each_with_index { |n, i| @f.store(evaluate ? evaluate.call(n) : expr(n), @rec, value_offset(base + i)) }
        result = yield(@f.iadd(@rec, imm(value_offset(base))), base)
        release(base)
        result
      end

      # The slots from `base` up are free again, and hold nothing the
      # collector would keep alive.
      def release(base)
        (base...@sp).each { |i| @f.store(@qnil, @rec, value_offset(i)) } unless @f.terminated?
        @sp = base
      end

      # A call into the kernel, typed from the def's own signature.
      def kernel(name, *args)
        d = @l.kernel_def(name)
        params = d.params.map { |_, type| Machine::TYPES.fetch(type) }
        ret = Machine::TYPES.fetch(d.ret)
        raise ArgumentError, "#{name} takes #{params.size} arguments, not #{args.size}" if params.size != args.size

        fn = @f.callee(name, params, ret, effects: d.effects || IR::Effects::ALL)
        ret ? @f.call_val(fn, args) : @f.call(fn, args)
      end

      def imm(n)
        @f.iconst("i64", n)
      end

      def qundef
        imm(@l.const("QUNDEF"))
      end

      # The program's id for `name`, as a value. Where the id is one no
      # program can move -- a name the runtime already spells -- it is
      # an immediate; every other name is a word in this unit's pool
      # that the link fills in, which is what keeps the unit's code free
      # of the order it was compiled in.
      def sym_word(name) = pooled(:symid, name) { |id| imm(id) }

      # `name` as a Symbol Value.
      def sym_value(name) = pooled(:symval, name) { |id| imm(Lower.symbol_value(id, @l.const("SYMBOL_TAG"))) }

      # The bit an ivar table's `names` keeps for `name`
      # (rt/kernel/object.rb, zr_ivtab_name_bit).
      def sym_bit(name) = pooled(:symbit, name) { |id| imm(Lower.ivar_name_bit(id)) }

      # This literal site's slot in the run-time table of literal
      # objects: a word the link numbers, as a symbol id is, so that a
      # unit carries no counter the whole program shares.
      def site_word
        row = @l.pool_site or return imm(@l.literal_index)

        @f.hoisted_fetch("i64", @f.symbol_addr(@f.symbol(row.first)), row.last)
      end

      def pooled(kind, name)
        id = @l.fixed_id(name)
        return yield(id) if id

        data, at = @l.pool_word(kind, name)
        @f.hoisted_fetch("i64", @f.symbol_addr(@f.symbol(data)), at)
      end

      def proc_field(name)
        @f.fetch("i64", @proc, off(@proc_layout, name))
      end

      # This frame's serial, given now when it has none yet: a block
      # descriptor carries it, so a later frame at the same address is
      # told from this one (`zr_frame_live`).
      def frame_serial
        have = @f.fetch("i64", @rec, off(@frame, "serial"))
        give = @f.label
        keep = @f.label
        merge, (serial,) = @f.block(["i64"])
        @f.brif(@f.icmp("eq", have, imm(0)), give, keep)
        switch(keep)
        @f.jump(merge, [have])
        switch(give)
        @f.jump(merge, [kernel("zr_frame_serial", @rec)])
        switch(merge)
        serial
      end

      # In a method: a field of the entry it was called through.
      def entry_field(name)
        @f.fetch("i64", arg_entry, off(@l.layout("MEntry"), name))
      end

      # In a block function: whether this Proc is a lambda.
      def lambda?
        @f.icmp("ne", proc_field("lambda"), imm(0))
      end

      # In a block function: `return`, `break` and `next` leave a lambda
      # itself with `v`; a plain block does what the block does.
      def unless_lambda(v)
        plain = @f.label
        own = @f.label
        @f.brif(lambda?, own, plain)
        switch(own)
        leave(through_ensures(v))
        switch(plain)
        yield
      end

      def off(layout, field)
        layout.fields.fetch(field).first
      end

      def global(name)
        @f.fetch("i64", static("globals"), 8 * @l.const(name))
      end

      # The class the cref names innermost: where a def or a constant lands.
      def cref_class
        kernel("zr_cref_klass", @cref)
      end

      def value_offset(i)
        @frame.size + (8 * i)
      end
    end
  end
end
