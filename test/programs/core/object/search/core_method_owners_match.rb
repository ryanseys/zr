
# The methods each core class and module defines itself, by visibility,
# and the constants it holds, as ruby 4.0 lists them. Names that rubygems
# and irb's Binding#irb define are left out, and so is RubyVM's parse.y
# surface: the ISEQ class and the AST's nodes.
LATER = %i[Gem RUBYGEMS_ACTIVATION_MONITOR irb InstructionSequence Location Node parse parse_file].freeze
GEMS = %i[gem gem_original_require require require_relative].freeze
mods = [BasicObject, Object, Kernel, Module, Class, Comparable, Enumerable, NilClass, TrueClass, FalseClass,
        Integer, Float, Numeric, Rational, Complex, String, Symbol, Array, Hash, Range, Struct, Data, Set,
        Proc, Method, UnboundMethod, Binding, Exception, StandardError, NameError, NoMethodError, KeyError,
        StopIteration, FrozenError, SystemExit, SignalException, SystemCallError, UncaughtThrowError,
        IO, File, File::Stat, Dir, Time, Random, Regexp, MatchData, Encoding, Encoding::Converter,
        Enumerator, Enumerator::Lazy, Enumerator::Yielder, Enumerator::Generator, Enumerator::Chain,
        Enumerator::ArithmeticSequence, Enumerator::Product,
        Thread, Thread::Mutex, Thread::Queue, Thread::SizedQueue, Thread::ConditionVariable, ThreadGroup,
        Fiber, Process::Status, ObjectSpace::WeakMap, ObjectSpace::WeakKeyMap, Marshal, Math, GC, Process,
        Signal, Warning, TracePoint, Ractor, Refinement, ObjectSpace, FileTest, Errno::ENOENT,
        RubyVM, RubyVM::AbstractSyntaxTree, RubyVM::YJIT]
mods.each do |m|
  rows = {
    public: m.public_instance_methods(false),
    protected: m.protected_instance_methods(false),
    private: m.private_instance_methods(false) - GEMS,
    singleton: m.singleton_methods(false),
    constants: m.constants(false)
  }
  rows.each do |kind, names|
    names -= LATER
    puts "#{m} #{kind}: #{names.sort.join(' ')}"
  end
end




