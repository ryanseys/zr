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
    # @rbs @highlights: Hash[String, String]
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
    # most programs that can eval never do. A Ractor other than main
    # reaches it through OnMain, because the back end's objects are the
    # main Ractor's.
    #: () -> (Eval | OnMain)
    def self.current
      return OnMain.new unless Ractor.main?

      @current || LOADING.synchronize { @current ||= plainly { (@backend || raise(NotImplementedError, "no back end of eval")).start } }
    end

    # Each call of the back end from a Ractor other than main runs on the
    # main Ractor, as rb_ractor_require runs a require there; its result
    # or its error comes back to the Ractor that called.
    class OnMain < BasicObject
      #: (Symbol name, *untyped args, **untyped options) ?{ (*untyped) -> untyped } -> untyped
      def method_missing(name, *args, **options, &block)
        ::Ractor.__send__(:on_main) { Eval.current.__send__(name, *args, **options, &block) }
      end

      #: (Symbol name, ?bool include_all) -> bool
      def respond_to_missing?(name, include_all = false) = true
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

    # The Coverage module, when the program loaded it. It is reached by a
    # symbol: a constant that names it in code arms the trace events of the
    # build (`Loader#names_of?`), and this code only reports to it.
    #: () -> untyped
    def self.covering
      coverage = Object.const_defined?(:Coverage) && Object.const_get(:Coverage) #: untyped
      coverage.respond_to?(:compiled_lines!, true) ? coverage : nil
    end

    # Gives Coverage the lines and branches of an eval's tree. Under
    # `eval: true` it counts the eval's lines as lines of the eval's file.
    # Ruby gives the file as many lines as the code has newlines, after
    # the lines before the eval's first one.
    #: (untyped coverage, Hir::Program hir, String source, Integer line) -> void
    def self.cover_eval(coverage, hir, source, line)
      coverable = hir.coverable
      return if coverable.nil? || coverable.empty?

      size = source.b.count("\n") + line - 1
      coverage.send(:compiled_lines!, coverable.transform_values { |(_, lines)| [size, lines] }, hir.defs, true, hir.branches)
    end

    #: () -> void
    def initialize
      @file_spots = {}
      @highlights = {}
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

    # error_highlight's spots of a file that a load or require compiled
    # at run time, found when an error first asks for them, as ruby
    # parses the file again then: the compile itself must not load
    # error_highlight, which is the program's autoload. Nil for a file
    # that no run-time compile read.
    #: (String path) -> String?
    def highlight_spots(path)
      return nil unless @file_spots.key?(path)

      @highlights[path] ||= Eval.plainly { Hir::Spots.of(Prism.parse(File.read(path), filepath: path).value) }
    end

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
