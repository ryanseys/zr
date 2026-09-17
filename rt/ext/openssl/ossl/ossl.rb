# frozen_string_literal: true

# ossl.c: the OpenSSL module, its versions and errors, and the helpers
# every other file shares (the Ossl module: ossl_raise and its kin, the
# PEM password callback, to_der).
module OpenSSL
  Lib.attach_all(
    OPENSSL_init_ssl: [%i[uint64 pointer], :int],
    OpenSSL_version: [%i[int], :string],
    OpenSSL_version_num: [[], :ulong],
    CRYPTO_memcmp: [%i[buffer buffer size_t], :int],
    CRYPTO_free: [%i[pointer string int], :void],
    ERR_get_error: [[], :ulong],
    ERR_peek_last_error: [[], :ulong],
    ERR_get_error_all: [%i[buffer buffer buffer buffer buffer], :ulong],
    ERR_peek_last_error_all: [%i[buffer buffer buffer buffer buffer], :ulong],
    ERR_reason_error_string: [%i[ulong], :string],
    ERR_lib_error_string: [%i[ulong], :string],
    ERR_error_string: [%i[ulong pointer], :string],
    ERR_clear_error: [[], :void],
    EVP_default_properties_is_fips_enabled: [%i[pointer], :int],
    EVP_default_properties_enable_fips: [%i[pointer int], :int],
    PEM_def_callback: [%i[pointer int int pointer], :int],
    OBJ_NAME_do_all_sorted: [%i[int pointer pointer], :void]
  )

  module Lib
    ERR_SYSTEM_FLAG = 0x8000_0000 # err.h
    ERR_REASON_MASK = 0x7FFFFF

    # ERR_GET_REASON (err.h).
    def self.ERR_GET_REASON(code) = code & ERR_SYSTEM_FLAG == 0 ? code & ERR_REASON_MASK : code & 0x7fff_ffff

    OPENSSL_VERSION = 0 # crypto.h
    ERR_TXT_STRING = 0x02 # err.h
    PEM_BUFSIZE = 1024 # pem.h

    # OPENSSL_free (crypto.h).
    def self.OPENSSL_free(address) = CRYPTO_free(address, "", 0)
  end

  raise RuntimeError, "OPENSSL_init_ssl" if Lib.OPENSSL_init_ssl(0, nil).zero?

  VERSION_TEXT = Lib.OpenSSL_version(Lib::OPENSSL_VERSION).force_encoding(Encoding::US_ASCII).freeze
  private_constant :VERSION_TEXT

  # The C extension names the headers it was built against here, and the
  # library it runs on below; the port has only the library.
  OPENSSL_VERSION = VERSION_TEXT
  OPENSSL_LIBRARY_VERSION = VERSION_TEXT
  OPENSSL_VERSION_NUMBER = Lib.OpenSSL_version_num
  OPENSSL_FIPS = true

  def self.fixed_length_secure_compare(str1, str2)
    str1 = Ossl.string_value(str1)
    str2 = Ossl.string_value(str2)
    raise Ossl.error(ArgumentError, "inputs must be of equal length") if str1.bytesize != str2.bytesize

    Lib.CRYPTO_memcmp(str1, str2, str1.bytesize).zero?
  end

  module_function

  def fips_mode = !Lib.EVP_default_properties_is_fips_enabled(nil).zero?

  def fips_mode=(enabled)
    if enabled
      raise Ossl.error(OpenSSLError, "Turning on FIPS mode failed") if Lib.EVP_default_properties_enable_fips(nil, 1).zero?
    elsif Lib.EVP_default_properties_enable_fips(nil, 0).zero?
      raise Ossl.error(OpenSSLError, "Turning off FIPS mode failed")
    end
    enabled
  end

  # Generic error class for OpenSSL. All error classes in this library
  # inherit from this class.
  class OpenSSLError < StandardError
    # The OpenSSL error queue's entries when the exception was raised,
    # oldest first.
    def errors = instance_variable_get(:@errors)

    ruby2_keywords def detailed_message(*args)
      text = super
      errors = instance_variable_get(:@errors)
      return text unless errors.is_a?(Array)

      text = +text
      text << "\nOpenSSL error queue reported #{errors.size} errors:"
      errors.each { |error| text << "\n#{error}" }
      text
    end
  end

  def debug = Ossl.debug

  def debug=(value)
    Ossl.debug = value ? true : false
    value
  end

  # The errors left in OpenSSL's queue, which it empties.
  def errors
    errors = []
    until (code = Lib.ERR_get_error).zero?
      errors << Lib.ERR_error_string(code, nil).force_encoding(Encoding::US_ASCII)
    end
    errors
  end

  # The helpers of ossl.c that the other files share.
  module Ossl
    class << self
      # dOSSL: whether the error queue's entries are written to stderr as
      # they are dropped.
      attr_writer :debug

      def debug = @debug || false

      # ossl_make_error: an instance of `klass` whose message is `message`
      # followed by the reason of the newest error in OpenSSL's queue, and
      # whose #errors are the queue's entries, which it empties.
      def error(klass, message = nil)
        message = message.nil? ? "".b : message.b
        data, flags = Array.new(2) { Lib.buffer(8) }
        code = Lib.ERR_peek_last_error_all(nil, nil, nil, data, flags)
        errors = []
        unless code.zero?
          reason = Lib.ERR_reason_error_string(code)
          message << ": " unless message.empty?
          message << (reason || "(null)")
          text = Lib.pointer_at(data)
          message << " (#{Lib.string(text)})" if flags.unpack1("l") & Lib::ERR_TXT_STRING != 0 && !text.zero?
          collect_errors(errors)
        end
        exception = klass.new(message)
        exception.instance_variable_set(:@errors, errors)
        exception
      end

      # ossl_clear_error: empties the queue, writing each entry to stderr
      # when OpenSSL.debug is on.
      def clear_error = collect_errors(nil)

      # collect_errors_into.
      def collect_errors(into)
        debug = self.debug
        unless debug || into
          Lib.ERR_clear_error
          return
        end

        file, line, func, data, flags = Array.new(5) { Lib.buffer(8) }
        until (code = Lib.ERR_get_error_all(file, line, func, data, flags)).zero?
          lib = Lib.ERR_lib_error_string(code)
          reason = Lib.ERR_reason_error_string(code)
          function = Lib.pointer_at(func)
          entry = format("error:%08X:%s:%s:%s", code, lib, function.zero? ? "" : Lib.string(function), reason)
          if flags.unpack1("l") & Lib::ERR_TXT_STRING != 0
            text = Lib.pointer_at(data)
            entry << " (#{text.zero? ? "(null)" : Lib.string(text)})"
          end
          warn("error on stack: #{entry}") if debug
          into&.push(entry)
        end
      end

      # rb_check_frozen.
      def check_frozen(object)
        raise FrozenError.new("can't modify frozen #{object.class}: #{object.inspect}", receiver: object) if object.frozen?
      end

      # rb_warn: `message` at the program's line that called into the
      # extension, the frames of the port itself skipped as the C
      # extension has none.
      def warn(message)
        location = caller_locations.find { |frame| !Native.internal_path?(frame.path.to_s) }
        return Kernel.warn(message) if location.nil?

        Kernel.warn("#{location.path}:#{location.lineno}: warning: #{message}")
      end

      # OSSL_Check_Kind.
      def check_kind(object, klass)
        return if object.is_a?(klass)

        raise error(TypeError, "wrong argument (#{object.class})! (Expected kind of #{klass})")
      end

      # Check_Type(value, T_ARRAY).
      def check_array(value)
        raise TypeError, "wrong argument type #{type_name(value)} (expected Array)" unless value.is_a?(Array)
      end

      # An Integer a C struct's ex_data or callback argument carries in
      # place of a Ruby object, which #dereference gives back while
      # something else keeps the object alive; 0 stands for nil.
      def reference(object)
        return 0 if object.nil?

        @references ||= ObjectSpace::WeakMap.new
        @reference_id = (@reference_id || 0) + 1
        @references[@reference_id] = object
        @reference_id
      end

      def dereference(id) = id.zero? ? nil : @references&.[](id)

      # The DER an i2d function writes for `object`: its length first,
      # then its bytes, raising `klass` with `message` when either fails.
      def i2d(function, object, klass, message = nil)
        length = Lib.public_send(function, object, nil)
        raise error(klass, message) if length <= 0

        out = Lib.buffer(length)
        cursor = [Native.address(out)].pack("J")
        raise error(klass, message) if Lib.public_send(function, object, cursor) <= 0

        out.byteslice(0, cursor.unpack1("J") - Native.address(out))
      end

      # The struct a d2i function decodes from `der`, or 0.
      def d2i(function, der) = Lib.public_send(function, nil, [Native.address(der)].pack("J"), der.bytesize)

      # What `yield` writes into a new memory BIO, raising `klass` with
      # `message` when it answers false or 0.
      def bio_output(klass, message = nil)
        bio = Lib.BIO_new(Lib.BIO_s_mem)
        raise error(klass, message) if bio.zero?

        written = yield(bio)
        if written == false || written == 0
          Lib.BIO_free(bio)
          raise error(klass, message)
        end
        membio2str(bio)
      end

      # StringValue.
      def string_value(value)
        return value if value.is_a?(String)

        converted = String.try_convert(value)
        raise TypeError, "no implicit conversion of #{type_name(value)} into String" if converted.nil?

        converted
      end

      # StringValueCStr.
      def cstring_value(value)
        value = string_value(value)
        raise ArgumentError, "string contains null byte" if value.include?("\0")

        value
      end

      # NUM2LONG.
      def long(value)
        case value
        when Integer
          raise RangeError, "bignum too big to convert into 'long'" unless value.between?(-1 << 63, (1 << 63) - 1)

          value
        when Float
          raise RangeError, "float #{format("%-.10g", value)} out of range of integer" unless value >= -(1 << 63) && value < (1 << 63)

          value.truncate
        when nil then raise TypeError, "no implicit conversion from nil to integer"
        else long(integer(value))
        end
      end

      # NUM2INT.
      def int(value)
        number = long(value)
        raise RangeError, "integer #{number} too big to convert to 'int'" if number > 0x7fff_ffff
        raise RangeError, "integer #{number} too small to convert to 'int'" if number < -0x8000_0000

        number
      end

      # An optional int argument: 0 when nil.
      def optional_int(value) = value.nil? ? 0 : int(value)

      # NUM2UINT: an int's range, and an unsigned int's.
      def uint(value)
        number = long(value)
        raise RangeError, "integer #{number} too big to convert to 'unsigned int'" if number > 0xffff_ffff
        raise RangeError, "integer #{number} too small to convert to 'unsigned int'" if number < -0x8000_0000

        number & 0xffff_ffff
      end

      # NUM2ULONG, which NUM2UINT64T is on a 64-bit machine: from -2**63,
      # which C reads as unsigned, up to 2**64 - 1.
      def uint64(value)
        case value
        when Integer
          raise RangeError, "bignum too big to convert into 'unsigned long'" if value >= 1 << 64
          raise RangeError, "bignum out of range of unsigned long" if value < -(1 << 63)

          value & Lib::WORD_MASK
        when Float
          raise RangeError, "float #{format("%-.10g", value)} out of range of integer" unless value > -(1 << 63) - 1 && value < (1 << 64)

          value.truncate & Lib::WORD_MASK
        when nil then raise TypeError, "no implicit conversion from nil to integer"
        else uint64(integer(value))
        end
      end
      alias ulong uint64

      # NUM2DBL.
      def double(value)
        case value
        when Float then value
        when Integer, Rational then value.to_f
        when String then raise TypeError, "no implicit conversion to float from string"
        when nil, true, false then raise TypeError, "no implicit conversion to float from #{value.inspect}"
        else Float(value)
        end
      end

      # rb_to_int: an Integer through to_int, or a TypeError.
      def integer(value)
        raise TypeError, "no implicit conversion of #{type_name(value)} into Integer" unless value.respond_to?(:to_int, true) && !(value == true || value == false)

        converted = value.__send__(:to_int)
        raise TypeError, "can't convert #{value.class} to Integer (#{value.class}#to_int gives #{converted.class})" unless converted.is_a?(Integer)

        converted
      end

      # rb_get_kwargs with every keyword required: the values of `names`
      # in `options`, raising as ruby does for one missing or one unknown.
      def keywords(options, *names)
        missing = names.reject { |name| options.key?(name) }
        raise ArgumentError, "missing keyword#{"s" if missing.size > 1}: #{missing.map(&:inspect).join(", ")}" unless missing.empty?

        unknown = options.keys - names
        raise ArgumentError, "unknown keyword#{"s" if unknown.size > 1}: #{unknown.map(&:inspect).join(", ")}" unless unknown.empty?

        options.values_at(*names)
      end

      # How ruby's conversion errors name a value's class.
      def type_name(value)
        case value
        when nil then "nil"
        when true then "true"
        when false then "false"
        else value.class.to_s
        end
      end

      # ossl_to_der.
      def to_der(object) = string_value(object.to_der)

      # ossl_to_der_if_possible.
      def to_der_if_possible(object) = object.respond_to?(:to_der) ? to_der(object) : object

      # ossl_pem_passwd_value.
      def pem_password_value(password)
        return nil if password.nil?

        password = string_value(password)
        raise error(OpenSSLError, "password must not be longer than #{Lib::PEM_BUFSIZE} bytes") if password.bytesize > Lib::PEM_BUFSIZE

        password
      end

      # Runs `yield` with `password` and `block` where PEM_PASSWORD_CB
      # finds them: the Integer to pass as the callback's data argument.
      def with_password(password, block)
        @passwords ||= {}
        @password_id = (@password_id || 0) + 1
        id = @password_id
        @passwords[id] = [password, block]
        yield id
      ensure
        @passwords.delete(id)
      end

      # ossl_pem_passwd_cb: the password `with_password` holds, or what its
      # block answers, copied into OpenSSL's buffer; -1 when there is none.
      def pem_password(buffer, max_length, flag, id)
        password, block = @passwords&.fetch(id, nil)
        unless password.nil?
          return -1 unless password.is_a?(String) && password.bytesize <= max_length

          Lib.write(buffer, password)
          return password.bytesize
        end
        return Lib.PEM_def_callback(buffer, max_length, flag, nil) if block.nil?

        loop do
          password = begin
            given = block.call(flag != 0)
            given.nil? ? nil : string_value(given)
          rescue Exception # rubocop:disable Lint/RescueException
            return -1
          end
          return -1 if password.nil?

          if password.bytesize > max_length
            warn "password must not be longer than #{max_length} bytes" if $VERBOSE
            next
          end
          Lib.write(buffer, password)
          return password.bytesize
        end
      end
    end

    PEM_PASSWORD_CB = Lib.callback { |buffer, size, flag, data| pem_password(buffer, size, flag, data) }

    # A C object a Ruby object owns: freed by `free`, a Lib function's
    # name or a Proc, once the collector takes this handle. The handle is
    # a separate object so that a copy of the Ruby object, which shares
    # it until initialize_copy sets its own, never frees it twice.
    class Handle
      attr_reader :address

      def initialize(address, free)
        @address = address
        ObjectSpace.define_finalizer(self, Handle.release(free, address)) if free
      end

      def self.release(free, address)
        free.is_a?(Proc) ? proc { free.(address) } : proc { Lib.public_send(free, address) }
      end

      # The address, which the handle no longer frees: the library took
      # the struct over, or freed it itself.
      def take
        ObjectSpace.undefine_finalizer(self)
        @address
      end
    end

    # A C struct type the port wraps, as an rb_data_type_t describes one:
    # `name`, which a TypeError names, `klass`, whose instances hold one,
    # `free`, which frees it, what the Get macro raises for an object that
    # holds none, and `alloc`, the allocator that makes one with the
    # object, where the C extension's allocation function does; it is
    # given the object when it takes an argument.
    class DataType
      attr_reader :name

      def initialize(name, klass, free, missing = nil, alloc: nil)
        @name = name
        @klass = klass
        @free = free
        @missing = missing
        @alloc = alloc
      end

      # TypedData_Get_Struct: the address `object` holds, or nil when
      # nothing set one yet; a TypeError for an object of another type.
      def get(object)
        check(object)
        handle = Native.hidden_get(object, :data)
        return handle.address if handle
        return nil unless @alloc

        set(object, @alloc.arity == 1 ? @alloc.call(object) : @alloc.call)
      end

      # The Get macro: #get, raising when nothing is set.
      def fetch(object)
        get(object) || raise(*@missing)
      end

      # RTYPEDDATA_DATA(object) = address: `object` owns the struct from
      # here, and frees it once it is collected.
      def set(object, address)
        Native.hidden_set(object, :data, address.nil? || address.zero? ? nil : Handle.new(address, @free))
        address
      end

      # The address `object` holds, which it no longer owns, for a library
      # call that frees or replaces the struct; the object holds nothing
      # until #set.
      def take(object)
        check(object)
        handle = Native.hidden_get(object, :data)
        Native.hidden_set(object, :data, nil)
        handle&.take
      end

      # The object holds `address` without owning it: a struct the library
      # lends for the length of a callback.
      def borrow(object, address)
        Native.hidden_set(object, :data, Handle.new(address, nil))
        object
      end

      # TypedData_Wrap_Struct: a new instance of `klass` owning `address`.
      def wrap(klass, address)
        object = Native.allocate(klass)
        set(object, address)
        object
      end

      # A copy begins as allocate leaves an object: the handle it took
      # from `original` stays the original's.
      def unshare(copy, original)
        Native.hidden_set(copy, :data, nil) if Native.hidden_get(copy, :data).equal?(Native.hidden_get(original, :data))
      end

      def check(object)
        return if object.is_a?(@klass)

        raise TypeError, "wrong argument type #{Ossl.type_name(object)} (expected #{@name})"
      end
    end

    class << self
      # What a C iteration hands its callback, in its order: `yield` runs
      # the iteration with COLLECT_CB and the data argument to give it.
      # OBJ_NAME_do_all_sorted, OSSL_PROVIDER_do_all and lh_doall_arg all
      # call back with the item first and the data argument second.
      def collect
        @collections ||= {}
        id = @collection_id = (@collection_id || 0) + 1
        @collections[id] = items = []
        yield COLLECT_CB, id
        items
      ensure
        @collections.delete(id)
      end

      def collected(item, id)
        @collections[id] << item
        1
      end

      # The names OBJ_NAME_do_all_sorted lists for `type`, in its order.
      def names(type)
        objects = collect { |callback, id| Lib.OBJ_NAME_do_all_sorted(type, callback, id) }
        # OBJ_NAME: int type, int alias, const char *name, const char *data.
        objects.map { |object| Lib.string(Lib.read_pointer(object + 8)) }
      end
    end

    COLLECT_CB = Lib.callback { |item, id| collected(item, id) }
  end
  private_constant :Ossl
end
