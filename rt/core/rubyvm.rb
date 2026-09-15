# RubyVM: what CRuby tells a program about its virtual machine. This
# runtime compiles every file with prism ahead of time, so it answers as a
# CRuby whose instruction sequences prism compiled, with YJIT off.
class RubyVM
  Primitive.zr_undef_alloc(self)

  class << self
    undef_method :new
  end

  OPTS = ["direct threaded code", "operands unification", "inline method cache"].freeze
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
    raise TypeError, "non-hash or symbol given" unless key.is_a?(Symbol)

    stats.fetch(key) { raise ArgumentError, "unknown key: #{key}" }
  end

  module AbstractSyntaxTree
    # The AST of what `body` runs. Every ISEQ here is prism's, so a body
    # written in Ruby refuses as ast_s_of refuses one; a method or a Proc
    # the runtime carries has no ISEQ and answers nil.
    def self.of(body, keep_script_lines: RubyVM.keep_script_lines, error_tolerant: false, keep_tokens: false)
      written = case body
                when Thread::Backtrace::Location then true
                when Proc, Method, UnboundMethod then !body.source_location.nil?
                else raise TypeError, "wrong argument type #{body.class} (expected method)"
                end
      raise RuntimeError, "cannot get AST for ISEQ compiled by prism" if written

      nil
    end

    # The id of the prism node that the location's line ran, or nil
    # where no Ruby code ran there.
    def self.node_id_for_backtrace_location(backtrace_location)
      raise TypeError, "Thread::Backtrace::Location object expected" unless backtrace_location.is_a?(Thread::Backtrace::Location)

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
    def self.stats_string = ""
    def self.insns_compiled(iseq) = nil
    def self.exit_locations = nil
    def self.log = nil
    def self.reset_stats! = false
    def self.code_gc = nil
    def self.disasm(iseq) = nil
    def self.dump_exit_locations(filename) = nil
    def self.simulate_oom! = nil
  end
end
