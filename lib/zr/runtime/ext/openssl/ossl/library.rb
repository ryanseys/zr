# frozen_string_literal: true

module OpenSSL
  # libssl and libcrypto 3, as the host installs them: found and opened
  # once, when the program requires openssl. Each file of the port binds
  # the functions it calls with Lib.attach, which gives the module a
  # method with the C name, and writes the header macros it uses as Ruby
  # next to them. A function that this library does not have gets no
  # method, so `Lib.respond_to?(name)` gives the same result as extconf.rb's have_func.
  module Lib
    # The oldest release the port runs on: OpenSSL 3.0.0.
    MINIMUM_VERSION = 0x30000000

    WORD_BITS = 64
    WORD_MASK = (1 << WORD_BITS) - 1
    SIGN_BIT = 1 << (WORD_BITS - 1)

    # How each C return value becomes a Ruby value, from the signed word
    # in x0. A narrower type takes the low bits, as C's caller does.
    RETURNS = {
      void: ->(_) {},
      int: ->(word) { ((word & 0xffff_ffff) ^ 0x8000_0000) - 0x8000_0000 },
      uint: ->(word) { word & 0xffff_ffff },
      uchar: ->(word) { word & 0xff },
      long: ->(word) { word },
      int64: ->(word) { word },
      ulong: ->(word) { word & WORD_MASK },
      uint64: ->(word) { word & WORD_MASK },
      size_t: ->(word) { word & WORD_MASK },
      pointer: ->(word) { word & WORD_MASK },
      string: ->(word) { word.zero? ? nil : Lib.string(word & WORD_MASK) }
    }.then { |table| Ractor.make_shareable(table) }

    PARAMS = %i[int uint uchar long int64 ulong uint64 size_t pointer string buffer double].freeze
    # The parameters C passes in 32 bits.
    NARROW = %i[int uint uchar].freeze

    class << self
      # The directories searched for the library, most specific first:
      # OPENSSL_DIR's lib alone when it is set.
      def directories
        if (prefix = ENV["OPENSSL_DIR"]) && !prefix.empty?
          [File.join(prefix, "lib")]
        elsif RUBY_PLATFORM.include?("darwin")
          # Never /usr/lib: macOS's libssl there ends the process that
          # opens it.
          %w[/opt/homebrew/opt/openssl@3/lib /usr/local/opt/openssl@3/lib /opt/local/lib]
        else
          %w[/usr/lib /usr/local/lib /usr/lib64]
        end
      end

      def file_name = RUBY_PLATFORM.include?("darwin") ? "libssl.3.dylib" : "libssl.so.3"

      # Opens libssl, whose image brings its own libcrypto, so every
      # symbol that the port binds comes through this one handle. Raises
      # LoadError with each searched path when none contains OpenSSL 3,
      # and at once in a static binary (aarch64-linux-musl), which has no
      # dynamic loader to open it with.
      def load
        return @handle if @handle
        if RUBY_PLATFORM.end_with?("-linux-musl")
          raise LoadError, "OpenSSL cannot load: this #{RUBY_PLATFORM} binary is static, and zr's openssl opens libssl.so.3 when it runs"
        end

        tried = []
        candidates = directories.map { |dir| File.join(dir, file_name) }
        # The dynamic loader's own search, where OPENSSL_DIR does not rule.
        candidates << file_name if ENV.fetch("OPENSSL_DIR", "").empty?
        candidates.each do |path|
          next tried << "#{path} (no such file)" if path.include?("/") && !File.exist?(path)

          handle = Native.open(path)
          next tried << "#{path} (#{Native.error})" if handle.nil?

          version = Native.symbol(handle, "OpenSSL_version_num")
          next tried << "#{path} (not OpenSSL)" if version.zero?

          number = RETURNS[:ulong].(Native.call(version, []))
          next tried << format("%s (OpenSSL %#x is older than 3.0)", path, number) if number < MINIMUM_VERSION

          @path = Ractor.make_shareable(path.dup)
          return @handle = handle
        end
        raise LoadError, "OpenSSL 3 was not found; set OPENSSL_DIR to its prefix. Looked for: #{tried.join(", ")}"
      end

      def path = @path

      # Binds `name`, a function that takes `params` and returns `returns`
      # (the names in PARAMS and RETURNS), as a method with that name.
      # Integers pass as they are, nil as NULL, true and false as 1 and
      # 0. A :string argument is text that C reads up to a NUL. A :buffer is
      # a String whose bytes C reads or writes in place. A :double (only the
      # last parameter can be one) is a Float. With `errno`, the method
      # returns [result, errno], with errno as it was when C returned. `as`
      # gives the method name when it is not the function's own name.
      def attach(name, params, returns, errno: false, as: name)
        address = Native.symbol(@handle, name.to_s)
        return if address.zero?

        unknown = params - PARAMS
        raise ArgumentError, "#{name}: unknown parameter types #{unknown}" unless unknown.empty?
        raise ArgumentError, "#{name}: only the last parameter may be a :double" if params[0...-1].include?(:double)

        answer = RETURNS.fetch(returns)
        arity = params.size
        strings = params.each_index.select { |i| params[i] == :string }.freeze
        double = params.last == :double
        raise ArgumentError, "#{name}: a :double call has no errno" if double && errno
        # Past eight arguments some go on the stack, where an int takes
        # four bytes: such a call goes through libffi with each width.
        widths = params.map { |type| NARROW.include?(type) ? 32 : 64 }.freeze if arity > 8
        raise ArgumentError, "#{name}: a call past eight arguments takes no :double or errno" if widths && (double || errno)
        # The function is a C function of libcrypto, which every Ractor
        # may call, so its method's block is shareable: it reads only
        # frozen values.
        call = Ractor.make_shareable(proc do |*args|
          raise ArgumentError, "wrong number of arguments (given #{args.size}, expected #{arity}) for #{name}" unless args.size == arity

          strings.each { |i| args[i] = Native.cstring(args[i]) if args[i].is_a?(String) }
          if widths
            answer.(Native.call_wide(address, widths, args.map! { |arg| Lib.word(arg) }))
          elsif double
            float = args.pop
            answer.(Native.call_double(address, args.map! { |arg| Lib.word(arg) }, float))
          elsif errno
            word, error = Native.call_errno(address, args.map! { |arg| Lib.word(arg) })
            [answer.(word), error]
          else
            answer.(Native.call(address, args.map! { |arg| Lib.word(arg) }))
          end
        end)
        define_singleton_method(as, &call)
      end

      # Binds each of `table`'s rows: name => [params, returns].
      def attach_all(table) = table.each { |name, (params, returns)| attach(name, params, returns) }

      # An argument as the signed word in x0-x7.
      def word(value)
        case value
        when Integer then value & SIGN_BIT == 0 ? value & WORD_MASK : (value & WORD_MASK) - (1 << WORD_BITS)
        when nil, false then 0
        when true then 1
        when String then Native.address(value)
        else value
        end
      end

      # -- memory ----------------------------------------------------------

      # `size` zero bytes C may write into: an out-parameter or an output
      # buffer, read back with unpack or byteslice.
      def buffer(size) = ("\0" * size).b

      def read(address, length) = length.zero? ? "".b : Native.read(address, length)

      # The NUL-ended text at `address`, in binary.
      def string(address) = Native.read(address, Native.strlen(address))

      def write(address, bytes) = Native.write(address, bytes)

      def read_pointer(address) = Native.read(address, 8).unpack1("J")

      def read_int(address) = Native.read(address, 4).unpack1("l")

      # The address in a buffer of pointers at `index`.
      def pointer_at(buffer, index = 0) = buffer.unpack1("J", offset: index * 8)

      # -- callbacks -------------------------------------------------------

      # A C function, for OpenSSL to call back, that runs `block` with its
      # arguments as signed Integers (seven of them; C passes fewer, and
      # the rest mean nothing) and returns the block's return value, an
      # Integer. Each is made once, where the C extension has a static
      # function, because the kernel keeps a fixed number of entries.
      # The table lives in hidden state and the dispatcher closes over it,
      # so a callback that runs in a Ractor other than main reads no
      # instance variable of the module, as a C static would be read.
      def callback(&block)
        table = Native.hidden_get(self, :callbacks)
        unless table
          table = []
          Native.hidden_set(self, :callbacks, table)
          Native.dispatch(->(index, args) { table[index].call(*args) })
        end
        table << block
        address = Native.callback(table.size - 1)
        raise ScriptError, "the port holds more C callbacks than the kernel has entries" if address.nil?

        address
      end
    end
  end
  private_constant :Lib
end
