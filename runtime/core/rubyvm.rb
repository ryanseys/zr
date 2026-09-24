# frozen_string_literal: true

# RubyVM: what CRuby tells a program about its virtual machine. This
# runtime compiles every file with prism ahead of time, so it answers as a
# CRuby whose instruction sequences prism compiled, with YJIT off.
class RubyVM
  Primitive.zr_undef_alloc(self)

  class << self
    undef_method :new
  end

  OPTS = ["direct threaded code", "operands unification", "inline method cache"]
  DEFAULT_PARAMS = {
    thread_vm_stack_size: 1_048_576,
    thread_machine_stack_size: 1_048_576,
    fiber_vm_stack_size: 131_072,
    fiber_machine_stack_size: 524_288
  }.freeze
  INSTRUCTION_NAMES = [].freeze

  KEEP_SCRIPT_LINES = [false]
  private_constant :KEEP_SCRIPT_LINES

  def self.keep_script_lines = KEEP_SCRIPT_LINES[0]

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
  # string compiled by the compiler a program that names this class
  # carries. There is no bytecode to show, so the forms that read it
  # refuse by name.
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

      def compile(source, file = +"<compiled>", path = file, line = 1, options = nil)
        source = source.read if source.is_a?(IO)
        return Primitive.zr_unimplemented(+"RubyVM::InstructionSequence.compile") unless defined?(::Zr::Eval)

        code = ::Zr::Eval.current.compile(source, file, line, [])
        Primitive.zr_box_compiled(code[1])
        iseq = made(nil, code, "<compiled>", "<compiled>", file, line)
        Primitive.zr_hidden_set(iseq, :__source__, source)
        Primitive.zr_hidden_set(iseq, :__absolute_path__, path)
        iseq
      end
      alias compile_prism compile
      alias new compile

      def compile_file(file, options = nil)
        iseq = compile(File.read(file), file, File.expand_path(file))
        Primitive.zr_hidden_set(iseq, :__label__, +"<main>")
        Primitive.zr_hidden_set(iseq, :__base_label__, +"<main>")
        iseq
      end
      alias compile_file_prism compile_file

      # The options CRuby's compiler starts with. Nothing here reads
      # them: a string compiles to machine code.
      COMPILE_OPTION = {
        inline_const_cache: true, peephole_optimization: true, tailcall_optimization: false,
        specialized_instruction: true, operands_unification: true, instructions_unification: false,
        debug_frozen_string_literal: false, coverage_enabled: true, debug_level: 0, frozen_string_literal: nil
      }.freeze

      def compile_option = COMPILE_OPTION.dup
      def compile_option=(options); end

      def disasm(body) = of(body)&.disasm
      alias disassemble disasm

      # There is no bytecode to load: every binary is one this runtime
      # cannot read.
      def load_from_binary(binary) = raise(RuntimeError, +"broken binary format")

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

    # The path as the file was found, or nil for code no file holds.
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

    def to_a = Primitive.zr_unimplemented(+"RubyVM::InstructionSequence#to_a")
    # The :line events a compiled string's top level fires: one on each
    # line a statement starts, as the compiler puts them.
    def trace_points
      code = Primitive.zr_hidden_get(self, :__source__)
      return Primitive.zr_unimplemented(+"RubyVM::InstructionSequence#trace_points of a block or a method") if code.nil?

      statements = ::Prism.parse(code, line: first_lineno).value.statements.body
      statements.select(&:newline?).map { |node| node.location.start_line }.uniq.map { |line| [line, :line] }
    end
    # The code a compiled string holds directly: each method, block and
    # class body it writes, in the order the compiler meets them. A
    # block's or a method's own code has no source kept to read.
    def each_child(&block)
      code = Primitive.zr_hidden_get(self, :__source__)
      return Primitive.zr_unimplemented(+"RubyVM::InstructionSequence#each_child of a block or a method") if code.nil?

      children = []
      nested(::Prism.parse(code, line: first_lineno).value, children)
      children.each(&block)
      self
    end

    # Only a whole program's code has a binary form.
    def to_binary(extra_data = nil)
      raise RuntimeError, +"should be top of iseq" if Primitive.zr_hidden_get(self, :__code__).nil?

      Primitive.zr_unimplemented(+"RubyVM::InstructionSequence#to_binary")
    end
    def script_lines = nil

    private

    # The child code under `node`, as iseqs made of their labels: a def
    # is its name, a block is "block in" the code around it, a class
    # body "<class:Name>". Their own children are theirs, not these.
    def nested(node, out)
      Primitive.attr! :hidden
      node.compact_child_nodes.each do |child|
        name = case child
               when ::Prism::DefNode then child.name.to_s
               when ::Prism::BlockNode, ::Prism::LambdaNode then "block in #{label}"
               when ::Prism::ClassNode then "<class:#{child.constant_path.slice}>"
               when ::Prism::ModuleNode then "<module:#{child.constant_path.slice}>"
               when ::Prism::SingletonClassNode then +"singleton class"
               end
        next nested(child, out) unless name

        base = child.is_a?(::Prism::BlockNode) || child.is_a?(::Prism::LambdaNode) ? label : name
        out << self.class.send(:made, nil, nil, name, base, path, child.location.start_line)
      end
    end
  end

  module AbstractSyntaxTree
    class Node; end
    class Location; end

    # The translator a program that names this module carries
    # (runtime/ext/zr/ast.rb), loaded ahead of the program's first line by
    # runtime/ext/zr/syntax_tree.rb. It defines the two classes above, so a
    # program that only names one of them finds it whole.
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

    # The AST of what `body` runs. Every ISEQ here is prism's, so a body
    # written in Ruby refuses as ast_s_of refuses one; a method or a Proc
    # the runtime carries has no ISEQ and answers nil.
    def self.of(body, keep_script_lines: RubyVM.keep_script_lines, error_tolerant: false, keep_tokens: false)
      written = case body
                when Thread::Backtrace::Location then true
                when Proc, Method, UnboundMethod then !body.source_location.nil?
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
      id.nil? || id.zero? ? nil : id
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
