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

      # The exception hierarchy the runtime carries natively. A `class` or
      # `module` naming one REOPENS it, exactly as `ALWAYS_ON` does -- the
      # `Errno::` block is left out because a program that reopens one
      # does not exist and the names are the platform's.
      EXCEPTIONS = %w[
      Exception ScriptError NotImplementedError LoadError StandardError
      ArgumentError EncodingError Encoding::UndefinedConversionError
      Encoding::InvalidByteSequenceError Encoding::CompatibilityError
      Encoding::ConverterNotFoundError IOError EOFError IndexError
      KeyError StopIteration NameError NoMethodError RangeError
      FloatDomainError LocalJumpError RegexpError RuntimeError FrozenError
      NoMatchingPatternError FiberError ThreadError ClosedQueueError
      RactorError TypeError ZeroDivisionError SystemCallError Errno
      Math::DomainError SyntaxError UncaughtThrowError SystemExit
      SignalException Interrupt NoMemoryError SecurityError
      SystemStackError NoMatchingPatternKeyError Regexp::TimeoutError
      IO::TimeoutError WeakRef::RefError Ractor::Error Ractor::ClosedError
      Ractor::IsolationError Ractor::MovedError Ractor::RemoteError
      Ractor::UnsafeError IO::Buffer::LockedError
      IO::Buffer::AllocationError IO::Buffer::AccessError
      IO::Buffer::InvalidatedError IO::Buffer::MaskError fatal
      IO::WaitReadable IO::WaitWritable IO::EAGAINWaitReadable
      IO::EAGAINWaitWritable IO::EINPROGRESSWaitReadable
      IO::EINPROGRESSWaitWritable
      ].freeze

      # The classes a require-gated builtin brings. A `class` or `module`
      # naming one REOPENS it, and the backend allows the row once the
      # feature is required -- but the LAYOUT is the runtime's, so the row
      # declares no instance variables of its own.
      GATED = %w[
      Addrinfo Base64 BasicSocket BigDecimal CGI CGI::Escape CGI::EscapeExt
      Coverage Date DateTime Digest Digest::Base Digest::Class
      Digest::Instance Digest::MD5 Digest::SHA1 Digest::SHA2 Digest::SHA256
      Digest::SHA384 Digest::SHA512 Etc Etc::Group Etc::Passwd FFI
      FFI::AbstractMemory FFI::AutoPointer FFI::DynamicLibrary FFI::Function
      FFI::MemoryPointer FFI::Pointer FFI::Struct FFI::Type FFI::Type::Builtin
      FFI::Union FFI::VariadicInvoker Fcntl IPSocket JSON Monitor NKF OpenSSL
      OpenSSL::BN OpenSSL::Buffering OpenSSL::Cipher OpenSSL::Digest
      OpenSSL::Digest::MD4 OpenSSL::Digest::MD5 OpenSSL::Digest::RIPEMD160
      OpenSSL::Digest::SHA1 OpenSSL::Digest::SHA224 OpenSSL::Digest::SHA256
      OpenSSL::Digest::SHA384 OpenSSL::Digest::SHA512 OpenSSL::HMAC
      OpenSSL::KDF OpenSSL::Random OpenSSL::SSL OpenSSL::SSL::SSLContext
      OpenSSL::SSL::SSLSocket OpenSSL::SSL::SocketForwarder OpenSSL::X509
      OpenSSL::X509::Certificate OpenSSL::X509::Name OpenSSL::X509::Store PTY
      Prism Psych Socket Socket::Constants Socket::Option StringIO
      StringScanner Syslog TCPServer TCPSocket UDPSocket UNIXServer UNIXSocket
      YAML Zlib Zlib::Deflate Zlib::Inflate Zlib::ZStream
      ].freeze

      # A `class << self` body is a class of its own -- `Owner`'s
      # singleton -- and this is the name its row carries. No Ruby
      # constant can collide with it, which is the point: the row exists
      # for the cref and for `Owner.singleton_class`, never for a
      # constant lookup.
      def self.singleton_of(owner) = "#<Class:#{owner}>"

      # Whether a `class` or `module` statement REOPENS what the runtime
      # already carries, rather than defining something new.
      def self.builtin?(name) = ALWAYS_ON.include?(name) || EXCEPTIONS.include?(name)

      # The builtin rows that are a NAMESPACE only: the class itself is a
      # Ruby file the compile splices, and the row exists so a nested
      # constant has a scope to sit in. Its parent is the one that file's
      # own superclass clause establishes, which is a compile-time write
      # to the row -- so ze0, which mints no rows, cannot make it.
      NAMESPACES = %w[WeakRef].freeze

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

    # A fully-qualified owner (`Outer::Inner`) as a symbol fragment. Each
    # segment is an identifier but for a singleton surrogate, whose name
    # is deliberately unspellable -- so each goes through the same escape
    # a method name does.
    def self.owner_fragment(owner)
      owner.to_s.split("::").map { |part| fragment(part) }.join("__")
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
