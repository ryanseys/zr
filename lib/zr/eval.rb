# frozen_string_literal: true

# The runtime's own libraries (lib/zr/runtime/lib/zr) call `Primitive`, so they
# run only inside a zr binary. Under ruby, nothing loads this file.
require_relative "runtime/lib/zr/eval/runtime"

module Zr
  # A string of ruby that the running program evals, or a file that it
  # requires and was not built with. A program carries one back end, a
  # subclass of this class, and the build picks it
  # (`Library::Roots.eval_file`): the compiler (`Eval::Compiler`) writes
  # machine code into the process, and the interpreter
  # (`Eval::Interpreter`) walks the tree where a program cannot write
  # code (a wasm module). The runtime calls the back end through
  # `Eval.current`.
  class Eval
    # @rbs @file_spots: Hash[String, String?]
    # @rbs @scripts: Array[String]
    # @rbs @script_sources: Array[[String, Integer]]

    # Two threads can eval at the same time. Only one of them starts the
    # back end, and the other waits until it has started. A trap handler
    # may eval, so it may take this lock (rb_mutex_allow_trap); a host
    # ruby has no such switch.
    LOADING = Thread::Mutex.new
    begin
      Thread::Mutex.send(:allow_trap, LOADING)
    rescue NoMethodError
      nil
    end

    # The back end is the subclass that loaded: a program links in one.
    #: (singleton(Eval) backend) -> void
    def self.inherited(backend)
      super
      @backend = backend
    end

    # The back end starts at the first eval, not when the program boots:
    # most programs that can eval never do.
    #: () -> Eval
    def self.current
      @current || LOADING.synchronize { @current ||= plainly { (@backend || raise(NotImplementedError, "no back end of eval")).start } }
    end

    # The back end's instance (`current`).
    #: () -> Eval
    def self.start = new

    # The front end runs with the plain collector. A collection at every
    # allocation (ZR_GC_STRESS) is for the program's own code. The
    # compiler leaves about 90,000 live objects, and an eval makes about
    # 30,000 allocations. Under stress, each allocation marks all of them
    # again, so one eval would take minutes.
    #
    # The program's separators ($, $; $/ $\) are set aside too: the
    # front end joins, splits and reads lines with ruby's defaults. And
    # its Enumerable methods walk Arrays and Hashes with the core's own
    # `each`, not one that the program redefines (Runtime.compiling).
    #: [T] () { () -> T } -> T
    def self.plainly(&)
      # `GC.stress=` has one overload for an Integer and one for a bool,
      # and Steep cannot give it the union that `GC.stress` returns.
      stress = GC.stress #: untyped
      begin
        GC.stress = false
        Runtime.plain_separators { Runtime.compiling(&) }
      ensure
        GC.stress = stress
      end
    end

    # Converts the argument to a String as ruby does: a String, or an
    # object that responds to `to_str`.
    #: (untyped value) -> String
    def self.string(value)
      return value if value.is_a?(String)
      raise TypeError, "no implicit conversion of #{name_of(value)} into String" unless value.respond_to?(:to_str)

      value.to_str
    end

    # How a conversion error names `value`: nil, true and false by
    # inspect, any other value by its class.
    #: (untyped value) -> String
    def self.name_of(value)
      value.nil? || value == true || value == false ? value.inspect : value.class.name.to_s
    end
    private_class_method :name_of

    #: () -> void
    def initialize
      @file_spots = {}
      @scripts = []
      @script_sources = []
    end

    # prism's tree of `source`, whose first line is `line`
    # (RubyVM::InstructionSequence reads it).
    #: (String source, Integer line) -> Prism::ProgramNode
    def parse(source, line) = Prism.parse(source, line: line).value

    # The spots (Hir::Spots) of the file at `path` that a load or require
    # compiled at run time, or nil.
    #: (String path) -> String?
    def file_spots(path) = @file_spots[path]

    # The spots (Hir::Spots) of the eval that `kept_script` numbered.
    #: (Integer number) -> String
    def script_spots(number) = @scripts.fetch(number - 1)

    # The source and first line of the eval that `kept_script` numbered.
    #: (Integer number) -> [String, Integer]
    def script_source(number) = @script_sources.fetch(number - 1)

    private

    # Keeps an eval's spots, as ruby keeps its script lines: its
    # Locations then find their source ranges. Its source and first line
    # stay too, for #syntax_tree. The number starts at 1.
    #: (String spots, String source, Integer line) -> Integer
    def kept_script(spots, source, line)
      @scripts << spots
      @script_sources << [source, line]
      @scripts.size
    end
  end
end
