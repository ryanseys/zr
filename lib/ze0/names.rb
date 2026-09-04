# frozen_string_literal: true

module Ze0
  # Symbol spellings, matching crates/zeo/src/names.rs and clif/names.rs so
  # a program ze0 writes names the same functions the Rust emitter would.
  module Names
      # The classes and modules the runtime always carries. A `class` or
      # `module` statement naming one REOPENS it: the id is the backend's and
      # no row may be minted beside it, so the body runs as a `class_eval`
      # on the constant instead. Transcribed from the rows of
      # `zeo_abi::BUILTINS` that name no feature, which
      # `checks::ze0_hygiene` compares this list against.
      ALWAYS_ON = %w[
      Object
      ARGF.class Array BasicObject Binding Class Comparable Complex Data Dir
      Encoding Encoding::Converter Enumerable Enumerator
      Enumerator::ArithmeticSequence Enumerator::Chain Enumerator::Generator
      Enumerator::Lazy Enumerator::Producer Enumerator::Product
      Enumerator::Yielder FalseClass Fiber File File::Constants File::Stat
      FileTest Float GC GC::Profiler Hash IO IO::Buffer IO::ConsoleMode
      Integer Kernel Marshal MatchData Math Method Module NilClass Numeric
      ObjectSpace ObjectSpace::WeakKeyMap ObjectSpace::WeakMap Pathname Proc
      Process Process::GID Process::Status Process::Sys Process::Tms
      Process::UID Process::Waiter Ractor Ractor::MovedObject Ractor::Port
      Random Random::Base Random::Formatter Range Rational Refinement Regexp
      Ruby Ruby::Box Ruby::Box::Entry Ruby::Box::Loader RubyVM
      RubyVM::AbstractSyntaxTree RubyVM::AbstractSyntaxTree::Location
      RubyVM::AbstractSyntaxTree::Node RubyVM::InstructionSequence
      RubyVM::YJIT Set Set::CoreSet Signal String Struct Symbol Thread
      Thread::Backtrace Thread::Backtrace::Location Thread::ConditionVariable
      Thread::Mutex Thread::Queue Thread::SizedQueue ThreadGroup Time
      TracePoint TrueClass UnboundMethod UnicodeNormalize Warning WeakRef Zeo
      Zeo::Eval
      ].freeze

    TOPLEVEL = "zeo_toplevel"
    # The owner of a top-level `def`.
    OBJECT = "Object"

    # A Ruby name as an identifier fragment: every character an identifier
    # grammar refuses becomes its `_uXXXX_` code point, reversibly.
    def self.fragment(name)
      name = name.to_s
      out = +""
      name.each_char.with_index do |c, i|
        ok = c == "_" || (i.zero? ? c.match?(/\A[\p{XID_Start}]\z/) : c.match?(/\A[\p{XID_Continue}]\z/))
        out << (ok ? c : format("_u%04X_", c.ord))
      end
      out
    end

    # A fully-qualified owner (`Outer::Inner`) as a symbol fragment. The
    # owner is already an identifier but for its separator.
    def self.owner_fragment(owner)
      owner.to_s.gsub("::", "__")
    end

    # The four channels a method body reaches the runtime through: an
    # instance method's body and its `ValueFn` trampoline, and the same
    # pair for a class method.
    def self.method_symbol(owner, name)
      "zeo_m_#{owner_fragment(owner)}_#{fragment(name)}"
    end

    def self.trampoline_symbol(owner, name)
      "zeo_t_#{owner_fragment(owner)}_#{fragment(name)}"
    end

    def self.class_method_symbol(owner, name)
      "zeo_cm_#{owner_fragment(owner)}_#{fragment(name)}"
    end

    def self.class_trampoline_symbol(owner, name)
      "zeo_ct_#{owner_fragment(owner)}_#{fragment(name)}"
    end

    # The frame labels a backtrace prints: an instance method, a class
    # method, and a class or module body.
    def self.method_label(owner, name)
      "#{owner}##{name}"
    end

    def self.class_method_label(owner, name)
      "#{owner}.#{name}"
    end

    def self.body_label(owner, kind)
      "<#{kind}:#{owner}>"
    end
  end
end
