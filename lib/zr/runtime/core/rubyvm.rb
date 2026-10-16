# frozen_string_literal: true

# RubyVM: what CRuby tells a program about its virtual machine. This
# runtime compiles every file with prism ahead of time, so it behaves as
# a CRuby whose instruction sequences prism compiled, with YJIT off.
class RubyVM
  Primitive.zr_undef_alloc(self)

  class << self
    undef_method :new
  end

  OPTS = ["direct threaded code", "operands unification", "inline method cache"]

  # vm_default_params_setup's get_param: the size an environment variable
  # gives (as atol reads it), at least `least`, rounded up to a page; else
  # the default.
  def self.param(name, default, least)
    Primitive.attr! :hidden
    text = Primitive.zr_environment_get(name) or return default
    size = [text.to_i, least].max
    (size + 4095) / 4096 * 4096
  end
  private_class_method :param

  DEFAULT_PARAMS = {
    thread_vm_stack_size: param("RUBY_THREAD_VM_STACK_SIZE", 1_048_576, 16_384),
    thread_machine_stack_size: param("RUBY_THREAD_MACHINE_STACK_SIZE", 1_048_576, 131_072),
    fiber_vm_stack_size: param("RUBY_FIBER_VM_STACK_SIZE", 131_072, 16_384),
    fiber_machine_stack_size: param("RUBY_FIBER_MACHINE_STACK_SIZE", 524_288, 131_072)
  }.freeze
  INSTRUCTION_NAMES = [].freeze

  KEEP_SCRIPT_LINES = [false]
  private_constant :KEEP_SCRIPT_LINES

  def self.keep_script_lines = KEEP_SCRIPT_LINES[0]

  # rb_profile_frame_*: the answer `what` about a frame of
  # rb_profile_frames, the code of the FrameMeta at `meta`
  # (kernel/capi/profile.rb). A C method's frame has no code, so no path,
  # label or first line, as ruby's entry of a C function has none. A
  # method's frame has its class, or none once the GC freed that class
  # (zr_meta_owners_drop); other code (a class body, a file) has none.
  def self.profile_frame(meta, what)
    Primitive.attr! :hidden
    form, owner, name = Primitive.zr_profile_meta(meta)
    iseq = InstructionSequence.send(:of_frame, meta) unless form == :cfunc
    case what
    when :path then iseq&.path
    when :absolute_path then form == :cfunc ? +"<cfunc>" : iseq.absolute_path
    when :label then iseq&.label
    when :base_label then iseq&.base_label
    when :first_lineno then iseq&.first_lineno
    when :classpath then profile_classpath(owner) unless form == :code
    when :singleton_method_p then form != :code && owner&.singleton_class? == true
    when :method_name then profile_method_name(form, name, iseq)
    when :qualified_method_name then profile_qualified(form, owner, profile_method_name(form, name, iseq))
    when :full_label then profile_full_label(form, owner, name, iseq)
    end
  end

  # The private iseq functions of the C API (kernel/capi/iseq.rb): the
  # answer `what` about the code of the FrameMeta at `meta`.
  def self.iseq_answer(meta, what, as_proc)
    Primitive.attr! :hidden
    iseq = InstructionSequence.send(:of_frame, meta)
    case what
    when :wrapper then iseq
    when :path then iseq.path
    when :realpath then iseq.absolute_path
    when :label then iseq.label
    when :first_lineno then iseq.first_lineno
    when :type then Primitive.zr_iseq_meta_info(meta)[2]
    when :parameters then Primitive.zr_iseq_meta_parameters_as(meta, as_proc)
    end
  end

  # rb_iseqw_to_iseq: the FrameMeta address of a RubyVM::InstructionSequence,
  # or nil for one that has none.
  def self.iseq_meta(iseqw)
    Primitive.attr! :hidden
    meta = Primitive.zr_hidden_get(iseqw, :__meta__) if iseqw.is_a?(InstructionSequence)
    meta if meta&.nonzero?
  end

  # rb_profile_frame_classpath: the path of the class, or of the module
  # whose singleton class it is, or `#<Class:0x...>` for another object's.
  def self.profile_classpath(owner)
    Primitive.attr! :hidden
    return nil if owner.nil?
    return owner.name || owner.inspect unless owner.singleton_class?

    attached = owner.attached_object
    attached.is_a?(Module) ? attached.name || attached.inspect : Kernel.instance_method(:to_s).bind_call(attached)
  end

  # rb_profile_frame_method_name: a C method's name, a Ruby method's, or
  # nil for code outside a method.
  def self.profile_method_name(form, name, iseq)
    Primitive.attr! :hidden
    case form
    when :cfunc then name.to_s
    when :method then iseq.base_label
    end
  end

  # rb_profile_frame_qualified_method_name: `Class#name`, `Class.name`,
  # or the name alone for code outside a method.
  def self.profile_qualified(form, owner, method_name)
    Primitive.attr! :hidden
    return nil if method_name.nil?
    return method_name if form == :code || owner.nil?

    "#{profile_classpath(owner)}#{owner.singleton_class? ? "." : "#"}#{method_name}"
  end

  # rb_profile_frame_full_label: the label with its method qualified, as
  # `block in Class#name`.
  def self.profile_full_label(form, owner, name, iseq)
    Primitive.attr! :hidden
    return profile_qualified(form, owner, name.to_s) if form == :cfunc

    qualified = profile_qualified(form, owner, profile_method_name(form, name, iseq))
    return iseq.label if qualified.nil? || iseq.base_label == qualified

    "#{iseq.label[0, iseq.label.length - iseq.base_label.length]}#{qualified}"
  end
  private_class_method :profile_frame, :profile_classpath, :profile_method_name, :profile_qualified, :profile_full_label, :iseq_answer, :iseq_meta

  def self.keep_script_lines=(flag)
    KEEP_SCRIPT_LINES[0] = flag ? true : false
  end

  def self.stat(key = nil)
    stats = { constant_cache_invalidations: 0, constant_cache_misses: 0, global_cvar_state: 0, next_shape_id: 0, shape_cache_size: 0 }
    return stats if key.nil?
    return stats.merge!(key) && key if key.is_a?(Hash)
    raise TypeError, +"non-hash or symbol given" unless key.is_a?(Symbol)

    stats.fetch(key) { raise ArgumentError, "unknown key: #{key}" }
  end

  # A handle on compiled code: a block or a method written in Ruby, or a
  # string compiled by the compiler that a program links in when it
  # refers to this class. There is no bytecode to show, so the forms
  # that read bytecode are refusals.
  class InstructionSequence
    Primitive.zr_undef_alloc(self)

    class << self
      def of(body)
        return nil unless Primitive.zr_iseq_p(body)

        path, line = body.source_location
        iseq = made(body, nil, Primitive.zr_iseq_label(body, false), Primitive.zr_iseq_label(body, true), path, line)
        Primitive.zr_hidden_set(iseq, :__meta__, Primitive.zr_iseq_meta_word(body))
        iseq
      end

      # The options come as a last Hash or as keywords. frozen_string_literal
      # is the one the compile reads; a magic comment of the source wins.
      def compile(source, file = +"<compiled>", path = file, line = 1, options = nil, **keywords)
        source = source.read if source.is_a?(IO)
        # A nil file is ruby's default, as irb's syntax check passes it.
        file = +"<compiled>" if file.nil?
        path = file if path.nil?
        return Primitive.zr_unimplemented(+"RubyVM::InstructionSequence.compile") unless defined?(::Zr::Eval)

        given = (options || {}).merge(keywords)
        frozen = given[:frozen_string_literal]
        # The option as a magic comment, on a line before the source's first.
        magic = "# frozen_string_literal: #{frozen ? true : false}\n" unless frozen.nil? || source.match?(/^#.*frozen[-_]string[-_]literal:/i)
        code = ::Zr::Eval.current.compile("#{magic}#{source}", file, magic ? line - 1 : line, [], warn_now: true,
                                                                                         debug_frozen: given[:debug_frozen_string_literal] ? true : false)
        Primitive.zr_box_compiled(code[1])
        iseq = made(nil, code, "<compiled>", "<compiled>", file, line)
        Primitive.zr_hidden_set(iseq, :__source__, source)
        Primitive.zr_hidden_set(iseq, :__absolute_path__, path)
        iseq
      end
      alias compile_prism compile
      alias compile_parsey compile
      alias new compile

      def compile_file(file, options = nil)
        file = Primitive.zr_convert_type(file, String, :to_str)
        source = begin
          File.read(file)
        rescue SystemCallError => e
          # pm_load_file: the error names the path alone.
          raise SystemCallError.new(file, e.errno), cause: nil
        end
        iseq = compile(source, file, File.expand_path(file))
        Primitive.zr_hidden_set(iseq, :__label__, +"<main>")
        Primitive.zr_hidden_set(iseq, :__base_label__, +"<main>")
        iseq
      end
      alias compile_file_prism compile_file

      # The options CRuby's compiler starts with. A string compiles to
      # machine code, so only `specialized_instruction` changes what an
      # eval compiles: without it, `new` is a send of Class#new.
      COMPILE_OPTION = {
        inline_const_cache: true, peephole_optimization: true, tailcall_optimization: false,
        specialized_instruction: true, operands_unification: true, instructions_unification: false,
        debug_frozen_string_literal: false, coverage_enabled: true, debug_level: 0, frozen_string_literal: nil
      }.freeze

      # What `compile_option = true` and `= false` give in the pinned ruby.
      COMPILE_OPTION_TRUE = COMPILE_OPTION.merge(
        peephole_optimization: false, specialized_instruction: false, operands_unification: false,
        coverage_enabled: false, debug_level: 1, frozen_string_literal: false
      ).freeze
      COMPILE_OPTION_FALSE = COMPILE_OPTION.to_h { |key, value| [key, value == true ? false : value] }.freeze
      private_constant :COMPILE_OPTION_TRUE, :COMPILE_OPTION_FALSE

      def compile_option = current_compile_option.dup

      # A Hash sets the options it names, true or false sets them all,
      # and nil changes nothing, as rb_iseq_compile_option_set does.
      def compile_option=(options)
        option = case options
                 when Hash then compile_option_from(options)
                 when true then COMPILE_OPTION_TRUE
                 when false then COMPILE_OPTION_FALSE
                 when nil then current_compile_option
                 else raise TypeError, "Compile option must be Hash/true/false/nil"
                 end
        Primitive.zr_state_set(self, :compile_option, option)
      end

      def current_compile_option
        Primitive.attr! :hidden
        Primitive.zr_hidden_get(self, :compile_option) || COMPILE_OPTION
      end
      private :current_compile_option

      # set_compile_option_from_hash: a known key takes the truth of its
      # value, debug_level an Integer; other keys are ignored.
      def compile_option_from(options)
        Primitive.attr! :hidden
        current_compile_option.to_h do |key, value|
          next [key, value] unless options.key?(key)

          given = options[key]
          case key
          when :debug_level then [key, Integer(given)]
          when :frozen_string_literal then [key, given.nil? ? nil : (given ? true : false)]
          else [key, given ? true : false]
          end
        end.freeze
      end
      private :compile_option_from

      def disasm(body) = of(body)&.disasm
      alias disassemble disasm

      # There is no bytecode to load: every binary is one this runtime
      # cannot read.
      def load_from_binary(binary) = raise(RuntimeError, +"broken binary format")
      def load_from_binary_extra_data(binary) = raise(RuntimeError, +"broken binary format")

      private

      # The code a frame runs, by the address of its FrameMeta, as a
      # debugger reads a frame's.
      def of_frame(meta_word)
        Primitive.attr! :hidden
        path, line = Primitive.zr_iseq_meta_info(meta_word)
        iseq = made(nil, nil, Primitive.zr_iseq_meta_label(meta_word, false), Primitive.zr_iseq_meta_label(meta_word, true), path, line)
        Primitive.zr_hidden_set(iseq, :__meta__, meta_word)
        iseq
      end

      def made(body, code, label, base_label, path, line)
        Primitive.attr! :hidden
        iseq = Primitive.zr_class_build(self)
        Primitive.zr_hidden_set(iseq, :__body__, body)
        Primitive.zr_hidden_set(iseq, :__code__, code)
        Primitive.zr_hidden_set(iseq, :__label__, label)
        Primitive.zr_hidden_set(iseq, :__base_label__, base_label)
        Primitive.zr_hidden_set(iseq, :__path__, path)
        Primitive.zr_hidden_set(iseq, :__first_lineno__, line)
        iseq
      end
    end

    def label = Primitive.zr_hidden_get(self, :__label__)
    def base_label = Primitive.zr_hidden_get(self, :__base_label__)
    def path = Primitive.zr_hidden_get(self, :__path__)
    def first_lineno = Primitive.zr_hidden_get(self, :__first_lineno__)

    # iseq_syntax_tree: the Ruby::Prism node of this code, from a parse of
    # its file again. A def gives its DefNode, a lambda its LambdaNode,
    # and a block the call that the block is for. A program that
    # compile_file made gives its ProgramNode. Nil where the code is not
    # from a file (an eval's), or the file changed since the compile.
    def syntax_tree
      body = Primitive.zr_hidden_get(self, :__body__)
      if body.nil?
        source = Primitive.zr_hidden_get(self, :__source__)
        path = Primitive.zr_hidden_get(self, :__absolute_path__)
        return nil unless source && path && File.file?(path) && Primitive.zr_hidden_get(self, :__label__) == "<main>"

        result = ::Ruby::Prism.parse_file(path, version: "current")
        return result.success? && InstructionSequence.send(:code_of, result) == InstructionSequence.send(:code_of, ::Ruby::Prism.parse(source)) ? result.value : nil
      end

      range = body.source_range or return nil
      # A kept eval's source parses from line 1, as ruby parses it again,
      # so its range's lines shift by the eval's first line.
      script = Primitive.zr_hidden_get(range, :__script__)
      tree, shift = if script&.positive? then InstructionSequence.send(:parse_script, script)
                    else [InstructionSequence.send(:parse_again, range.path, range.absolute_path), 0]
                    end
      return nil unless tree
      queue = [[tree, nil]]
      while (node, parent = queue.shift)
        if [node.start_line + shift, node.start_column, node.end_line + shift, node.end_column] == [range.start_line, range.start_column, range.end_line, range.end_column]
          case node.type
          # A `for` body is a block whose source is the whole loop.
          when :def_node, :lambda_node, :for_node then return node
          when :block_node then return parent
          end
        end
        node.compact_child_nodes.each { |child| queue << [child, node] }
      end
      nil
    end

    class << self
      private

      # The tree of the eval whose source RubyVM.keep_script_lines kept,
      # and how far its lines are from the eval's.
      def parse_script(number)
        Primitive.attr! :hidden
        source, line = ::Zr::Eval.current.script_source(number)
        result = ::Ruby::Prism.parse(source, version: "current")
        [result.success? ? result.value : nil, line - 1]
      end

      # The tree of the file at `absolute`, which the program compiled as
      # `path`: nil when there is no such file, or its code is no longer
      # what was compiled, or it does not parse.
      def parse_again(path, absolute)
        Primitive.attr! :hidden
        return nil unless absolute && File.file?(absolute)

        result = ::Ruby::Prism.parse_file(absolute, version: "current")
        return nil unless result.success?

        digest = Thread::Backtrace::Location.send(:digest_of, path)
        if digest
          code = code_of(result)
          return nil unless digest == [Primitive.zr_zlib_checksum(0, 0, Primitive.zr_str_operand(code)), code.bytesize]
        end
        result.value
      end

      # The code that prism parsed, up to the end of an `__END__` line.
      def code_of(result)
        Primitive.attr! :hidden
        code = result.source.source
        if (data = result.data_loc) && (eol = code.byteindex("\n", data.start_offset))
          code = code.byteslice(0, eol + 1)
        end
        code
      end
    end

    # The path where the file was found, or nil for code that is not from a file.
    def absolute_path
      Primitive.zr_hidden_get(self, :__absolute_path__) || (Primitive.zr_path_kind(path) == 2 ? File.expand_path(path) : nil)
    end

    # A compiled string runs at the top level, under main and Object. A
    # block's or a method's code is no whole program, as ruby says.
    def eval
      code = Primitive.zr_hidden_get(self, :__code__)
      raise TypeError, +"Not a toplevel InstructionSequence" if code.nil?

      Primitive.zr_eval_run(code, TOPLEVEL_BINDING.receiver, Primitive.zr_eval_cref_under(Object, nil), nil, nil)
    end

    def inspect = "<RubyVM::InstructionSequence:#{label}@#{path}:#{first_lineno}>"

    def disasm = Primitive.zr_unimplemented(+"RubyVM::InstructionSequence#disasm")
    alias disassemble disasm

    # pm_source_hash: the 64-bit FNV-1a hash of the source this code was
    # parsed from, up to the line of its __END__; nil when the source is
    # not at hand. A hash of 0 is 1.
    def source_hash
      code = Primitive.zr_hidden_get(self, :__source__)
      if code.nil?
        file = absolute_path || path
        code = File.binread(file) if Primitive.zr_hidden_get(self, :__body__) && file && File.file?(file)
      end
      return nil if code.nil?

      code = code.b
      if (data = code =~ /^__END__\r?(?:\n|\z)/n)
        stop = code.index("\n", data)
        code = code.byteslice(0, stop ? stop + 1 : code.bytesize)
      end
      hash = 0xcbf29ce484222325
      code.each_byte { |byte| hash = ((hash ^ byte) * 0x100000001b3) & 0xffffffffffffffff }
      hash.zero? ? 1 : hash
    end

    # The array of ruby's iseq_data_to_ary: its header, then the facts of
    # this code that the parse gives. zr compiles to machine code, so the
    # stack size, the catch table and the instruction list are empty.
    def to_a
      node = syntax
      locals = node.respond_to?(:locals) ? node.locals : []
      location = node&.location
      misc = { arg_size: 0, local_size: locals.size, stack_max: 0 }
      id = node_id
      misc[:node_id] = id if id
      misc[:source_hash] = source_hash
      misc[:code_location] = [location.start_line, location.start_column, location.end_line, location.end_column] if location
      misc[:parser] = :prism
      # ISEQ_MAJOR_VERSION and ISEQ_MINOR_VERSION are ruby's API version.
      major, minor = RUBY_VERSION.split(".").first(2).map(&:to_i)
      ["YARVInstructionSequence/SimpleDataFormat", major, minor, 1, misc, label, path, absolute_path, first_lineno, code_type, locals, {}, [],
       events]
    end

    # The body of `to_a`: zr has no instructions, so only the line of each
    # event, then the event, as ruby's list has them before each
    # instruction that fires one (a debugger reads the lines a body can
    # stop on from them).
    def events
      Primitive.attr! :hidden
      meta = Primitive.zr_hidden_get(self, :__meta__)
      points = if syntax then trace_points
               elsif meta && Primitive.zr_iseq_meta_lines(meta) then built_trace_points
               else []
               end
      points.flat_map { |line, event| [line, :"RUBY_EVENT_#{event.upcase}"] }
    end
    private :events

    # The id of this code's node in its parse (iseq_node_id): from the meta
    # of compiled code, else from the parse of a compiled string.
    def node_id
      meta = Primitive.zr_hidden_get(self, :__meta__)
      id = Primitive.zr_iseq_meta_node(meta) if meta
      id&.positive? ? id : syntax&.node_id
    end

    # :top for a compiled string, :method for a method's code and :block
    # for a block's.
    def code_type
      Primitive.attr! :hidden
      case Primitive.zr_hidden_get(self, :__body__)
      when Method, UnboundMethod then :method
      when Proc then :block
      else
        meta = Primitive.zr_hidden_get(self, :__meta__)
        meta ? Primitive.zr_iseq_meta_info(meta)[2] : :top
      end
    end
    private :code_type
    # The :line events of this code: each statement that starts a line,
    # as prism flags it, outside the methods, blocks and class bodies in
    # it, which are code of their own.
    def trace_points
      node = syntax
      return built_trace_points if node.nil?

      # The :call, :b_call or :class event of a def, block or class body
      # is on its first line, so a statement there gives no :line event.
      seed = scope?(node) ? [node.location.start_line] : []
      lines = seed.dup
      line_events(node, lines)
      lines.drop(seed.size).map { |line| [line, :line] }
    end

    # The code that this code contains directly: each method, block and
    # class body it writes, in the order the compiler finds them.
    def each_child(&block)
      node = syntax
      if node.nil?
        built_children.each(&block)
        return self
      end

      # The rescue and ensure clauses come first, from the catch table.
      handlers, rest = [], []
      nested(node, handlers, rest)
      handlers.each(&block)
      rest.each(&block)
      self
    end

    # Only a whole program's code has a binary form.
    def to_binary(extra_data = nil)
      raise RuntimeError, +"should be top of iseq" if Primitive.zr_hidden_get(self, :__code__).nil?

      Primitive.zr_unimplemented(+"RubyVM::InstructionSequence#to_binary")
    end
    def script_lines = nil

    private

    # The opening and closing events of each type of code.
    SCOPE_EVENTS = { method: %i[call return], block: %i[b_call b_return], class: %i[class end] }.freeze
    private_constant :SCOPE_EVENTS

    # The events of compiled code, from the lines that a traced build
    # keeps in its meta: the opening event on its first line, its :line
    # events, and the closing event on its last line.
    def built_trace_points
      Primitive.attr! :hidden
      meta = Primitive.zr_hidden_get(self, :__meta__)
      own, = (Primitive.zr_iseq_meta_lines(meta) if meta)
      return Primitive.zr_unimplemented(+"RubyVM::InstructionSequence#trace_points of a block or a method") if own.nil?

      _, first, type, last = Primitive.zr_iseq_meta_info(meta)
      opening, closing = SCOPE_EVENTS[type]
      points = own.map { |line| [line, :line] }
      opening ? [[first, opening], *points, [last, closing]] : points
    end

    # The code written directly in compiled code, from the scopes that a
    # traced build keeps in its meta.
    def built_children
      Primitive.attr! :hidden
      meta = Primitive.zr_hidden_get(self, :__meta__)
      children = Primitive.zr_iseq_meta_children(meta) if meta
      return Primitive.zr_unimplemented(+"RubyVM::InstructionSequence#each_child of a block or a method") if children.nil?

      children.map { |child| self.class.send(:of_frame, child) }
    end

    # The lines where a TracePoint that targets this code can fire :line
    # events: its own and those of the code in it; nil when the build kept
    # none.
    def target_lines
      Primitive.attr! :hidden
      if syntax
        trace_points.map(&:first)
      else
        meta = Primitive.zr_hidden_get(self, :__meta__)
        Primitive.zr_iseq_meta_lines(meta)&.last if meta
      end
    end

    # The child code under `node`, as iseqs made of their labels: a def
    # is its name, a block is "block in" the code around it, a class
    # body "<class:Name>". Their own children are theirs, not these.
    def nested(node, handlers, out)
      Primitive.attr! :hidden
      node.compact_child_nodes.each do |child|
        name = case child
               when ::Prism::DefNode then child.name.to_s
               when ::Prism::BlockNode, ::Prism::LambdaNode then "block in #{label}"
               when ::Prism::ClassNode then "<class:#{child.constant_path.slice}>"
               when ::Prism::ModuleNode then "<module:#{child.constant_path.slice}>"
               when ::Prism::SingletonClassNode then +"singleton class"
               when ::Prism::RescueNode then "rescue in #{label}" unless node.is_a?(::Prism::RescueNode)
               when ::Prism::EnsureNode then "ensure in #{label}"
               end
        next nested(child, handlers, out) unless name

        handler = child.is_a?(::Prism::RescueNode) || child.is_a?(::Prism::EnsureNode)
        base = handler || child.is_a?(::Prism::BlockNode) || child.is_a?(::Prism::LambdaNode) ? label : name
        # An ensure clause's code starts at its first statement.
        line = (child.statements&.location&.start_line if child.is_a?(::Prism::EnsureNode)) || child.location.start_line
        iseq = self.class.send(:made, nil, nil, name, base, path, line)
        Primitive.zr_hidden_set(iseq, :__syntax__, child)
        (handler ? handlers : out) << iseq
      end
    end

    # The tree of this code: the parsed string, or the node of a child.
    # The code of a running frame has neither.
    def syntax
      Primitive.attr! :hidden
      Primitive.zr_hidden_get(self, :__syntax__) || Primitive.zr_hidden_get(self, :__source__)&.then do |code|
        # The compiler that made this code parses it.
        Primitive.zr_hidden_set(self, :__syntax__, ::Zr::Eval.current.parse(code, first_lineno))
      end
    end

    # A :line event for each statement under `node` that starts a line
    # other than the last event's, as the compiler emits them, outside the
    # code of its own that a def, block, class body or rescue clause is.
    # An ensure clause is both: the compiler puts a copy of it inline.
    def line_events(node, lines)
      Primitive.attr! :hidden
      node.compact_child_nodes.each do |child|
        line = child.location.start_line
        live = live_branch(child)
        # A begin compiles to nothing before its first statement, whose
        # event takes the place of its own; so does a condition that is a
        # literal, which leaves only the branch it takes. With no branch,
        # the last statement of a list still gives its value, a nil.
        own = live.nil? || (live == false && node.is_a?(::Prism::StatementsNode) && child.equal?(node.body.last))
        lines << line if child.newline? && lines.last != line && !(child.is_a?(::Prism::BeginNode) && child.statements) && own
        next if scope?(child) || (child.is_a?(::Prism::RescueNode) && !node.is_a?(::Prism::RescueNode))
        if live
          # An elsif is a statement of its own there.
          lines << live.location.start_line if live.is_a?(::Prism::IfNode) && lines.last != live.location.start_line
          next line_events(live, lines)
        end
        next if live == false

        line_events(child, lines)
      end
    end

    # The branch that an if or unless with a literal condition takes (false
    # when there is none), or nil for any other node.
    def live_branch(node)
      Primitive.attr! :hidden
      return nil unless node.is_a?(::Prism::IfNode) || node.is_a?(::Prism::UnlessNode)

      truth = case node.predicate
              when ::Prism::TrueNode, ::Prism::IntegerNode, ::Prism::FloatNode, ::Prism::StringNode, ::Prism::SymbolNode then true
              when ::Prism::FalseNode, ::Prism::NilNode then false
              else return nil
              end
      taken = truth == node.is_a?(::Prism::IfNode) ? node.statements : (node.is_a?(::Prism::IfNode) ? node.subsequent : node.else_clause)
      taken || false
    end

    # Whether `node` is code of its own: a def, a block or a class body.
    def scope?(node)
      Primitive.attr! :hidden
      node.is_a?(::Prism::DefNode) || node.is_a?(::Prism::BlockNode) || node.is_a?(::Prism::LambdaNode) ||
        node.is_a?(::Prism::ClassNode) || node.is_a?(::Prism::ModuleNode) || node.is_a?(::Prism::SingletonClassNode)
    end
  end

  module AbstractSyntaxTree
    class Node; end
    class Location; end

    # The translator (lib/zr/runtime/lib/zr/ast.rb) that a program links in when
    # it refers to this module. lib/zr/runtime/lib/zr/syntax_tree.rb loads it
    # before the program's first line. It defines the two classes above,
    # so a program that refers to only one of them finds it complete.
    def self.translator
      Primitive.attr! :hidden
      ::Zr::AST
    end
    private_class_method :translator

    # The tree parse.y would build, which the translator rebuilds from
    # prism's.
    def self.parse(string, keep_script_lines: RubyVM.keep_script_lines, error_tolerant: false, keep_tokens: false)
      translator.parse(string, keep_script_lines: keep_script_lines, error_tolerant: error_tolerant, keep_tokens: keep_tokens)
    end

    def self.parse_file(pathname, keep_script_lines: RubyVM.keep_script_lines, error_tolerant: false, keep_tokens: false)
      translator.parse_file(pathname, keep_script_lines: keep_script_lines, error_tolerant: error_tolerant, keep_tokens: keep_tokens)
    end

    # The AST of the code that `body` runs. Every ISEQ here is prism's, so
    # a body written in Ruby refuses as ast_s_of refuses one. A method or a
    # Proc that the runtime includes, and an attribute, have no ISEQ and
    # return nil.
    def self.of(body, keep_script_lines: RubyVM.keep_script_lines, error_tolerant: false, keep_tokens: false)
      written = case body
                when Thread::Backtrace::Location then true
                when Proc, Method, UnboundMethod then Primitive.zr_iseq_p(body)
                else raise TypeError, "wrong argument type #{body.class} (expected method)"
                end
      raise RuntimeError, +"cannot get AST for ISEQ compiled by prism" if written

      nil
    end

    # The id of the prism node that the location's line ran, or nil
    # where no Ruby code ran there.
    def self.node_id_for_backtrace_location(backtrace_location)
      raise TypeError, +"Thread::Backtrace::Location object expected" unless backtrace_location.is_a?(Thread::Backtrace::Location)

      id = Primitive.zr_hidden_get(backtrace_location, :__node_id__)
      # Without the mark of a frame at a body's entry (Hir::Spots::ENTRY).
      id.nil? || id.zero? ? nil : id & 0x3fffffff
    end
  end

  module YJIT
    def self.enabled? = false
    def self.enable(**) = false
    def self.stats_enabled? = false
    def self.log_enabled? = false
    def self.trace_exit_locations_enabled? = false
    def self.runtime_stats(key = nil) = nil
    def self.stats_string = +""
    def self.insns_compiled(iseq) = nil
    def self.exit_locations = nil
    def self.log = nil
    def self.reset_stats! = nil
    def self.code_gc = nil
    def self.disasm(iseq) = nil
    def self.dump_exit_locations(filename)
      raise ArgumentError, +"--yjit-trace-exits must be enabled to use dump_exit_locations."
    end
    def self.simulate_oom! = nil
  end
end
