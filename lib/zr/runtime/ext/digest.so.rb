# frozen_string_literal: true

Object.send(:native_module, :Digest)

# digest.c, in ruby: Digest.hexencode, the Digest::Instance protocol,
# Digest::Class, and Digest::Base, which runs the algorithm that a
# subclass gives in its metadata. The extension's ruby part (digest.rb,
# vendored in vendor/ruby) uses it as it uses the C.
module Digest
  # An algorithm, as rb_digest_metadata_t describes one: which compression
  # the kernel runs, the chaining words it starts from, the lengths, and
  # the byte order of its words and its length field.
  # `hasher` runs an algorithm that keeps its own context (CRC32,
  # BLAKE3): init, update, finish and copy, in place of the compression.
  Metadata = Struct.new(:algorithm, :start, :digest_length, :block_length, :little_endian, :hasher)
  private_constant :Metadata

  def self.metadata(algorithm, start, digest_length, block_length, little_endian, hasher = nil)
    Primitive.attr! :hidden
    Metadata.new(algorithm, start, digest_length, block_length, little_endian, hasher).freeze
  end
  private_class_method :metadata

  def hexencode(str) = Primitive.zr_str_operand(str).unpack1("H*").force_encoding(Encoding::US_ASCII)
  module_function :hexencode

  module Instance
    def update(str) = raise(RuntimeError, "#{self.class} does not implement update()")
    alias << update

    def reset = raise(RuntimeError, "#{self.class} does not implement reset()")

    def digest_length
      digest = self.digest
      raise TypeError, no_implicit_conversion(digest, "String") unless digest.is_a?(String)

      digest.bytesize
    end

    def block_length = raise(RuntimeError, "#{self.class} does not implement block_length()")

    def ==(other)
      if other.is_a?(Digest::Instance)
        left = digest
        right = other.digest
      else
        left = to_s
        right = String.try_convert(other)
        return false if right.nil?
      end
      Primitive.zr_str_operand(left) == Primitive.zr_str_operand(right)
    end

    def inspect = "#<#{self.class.name}: #{hexdigest}>"

    def new
      copy = clone
      copy.reset
      copy
    end

    def digest(*args)
      raise ArgumentError, wrong_arity(args.size, 0..1) if args.size > 1
      return clone.__send__(:finish) if args.empty?

      reset
      update(args[0])
      value = __send__(:finish)
      reset
      value
    end

    def digest!
      value = __send__(:finish)
      reset
      value
    end

    def hexdigest(*args) = Digest.hexencode(digest(*args))

    def hexdigest! = Digest.hexencode(digest!)

    def to_s = hexdigest

    def length = digest_length
    alias size length

    private

    def finish = raise(RuntimeError, "#{self.class} does not implement finish()")
  end

  class Class
    include Instance

    def initialize = self

    def self.digest(*args)
      raise ArgumentError, "no data given" if args.empty?

      str = Primitive.zr_str_operand(args.shift)
      new(*args).digest(str)
    end

    def self.hexdigest(*args) = Digest.hexencode(digest(*args))
  end

  class Base < Class
    # T_DATA, of a type that is not frozen-shareable.
    Ractor.send(:data_class!, self)

    class << self
      # rb_digest_base_alloc refuses before anything is made.
      def allocate
        Primitive.attr! :hidden
        Base.send(:metadata_of, self)
        Primitive.zr_class_build(self)
      end

      def new(*args, &block)
        Primitive.attr! :hidden
        Base.send(:metadata_of, self)
        digest = Primitive.zr_class_build(self)
        digest.__send__(:initialize, *args, &block)
        digest
      end

      private

      # get_digest_base_metadata: the nearest class up the chain that
      # gives an algorithm.
      def metadata_of(klass)
        Primitive.attr! :hidden
        raise NotImplementedError, "Digest::Base is an abstract class" if klass.equal?(Base)

        at = klass
        at = at.superclass until at.nil? || Primitive.zr_hidden_get(at, :metadata)
        raise RuntimeError, "Digest::Base cannot be directly inherited in Ruby" if at.nil?

        Primitive.zr_hidden_get(at, :metadata)
      end
    end

    def initialize_copy(obj)
      return self if equal?(obj)

      Primitive.zr_frozen_error(self) if frozen?
      raise TypeError, "different algorithms" unless metadata.equal?(obj.send(:metadata))

      state, pending, length = obj.send(:context)
      state = (hasher = metadata.hasher) ? hasher.copy(state) : state.dup
      Primitive.zr_state_set(self, :__context__, [state, pending.dup, length])
      self
    end

    def reset
      start
      self
    end

    def update(str)
      str = Primitive.zr_str_operand(str)
      if (hasher = metadata.hasher)
        context[0] = hasher.update(context[0], str.b)
        return self
      end

      context[1] << str.b
      context[2] += str.bytesize
      compress
      self
    end
    alias << update

    def digest_length = metadata.digest_length

    def block_length = metadata.block_length

    private

    # rb_digest_base_finish: the padded message's last blocks, the words
    # as the digest, and the context started again.
    def finish
      meta = metadata
      if meta.hasher
        out = meta.hasher.finish(context[0])
        start
        return out
      end

      state, pending, length = context
      field = meta.block_length == 128 ? 16 : 8
      pending << "\x80".b
      pending << ("\0".b * ((meta.block_length - field - pending.bytesize) % meta.block_length))
      bits = length * 8
      pending << if meta.little_endian then [bits].pack("Q<")
                 elsif field == 16 then [bits >> 64, bits & 0xffff_ffff_ffff_ffff].pack("Q>Q>")
                 else [bits].pack("Q>")
                 end
      compress
      words = state.unpack("Q<8")
      out = if meta.little_endian then words.pack("V*")
            elsif meta.block_length == 128 then words.pack("Q>*")
            else words.pack("N*")
            end
      start
      out.byteslice(0, meta.digest_length)
    end

    def metadata
      Primitive.attr! :hidden
      Base.send(:metadata_of, self.class)
    end

    def context
      Primitive.attr! :hidden
      Primitive.zr_hidden_get(self, :__context__) || start
    end

    def start
      Primitive.attr! :hidden
      meta = metadata
      state = meta.hasher ? meta.hasher.init : Primitive.zr_digest_state(meta.start)
      Primitive.zr_state_set(self, :__context__, [state, "".b, 0])
    end

    def compress
      Primitive.attr! :hidden
      state, pending = context
      size = metadata.block_length
      whole = pending.bytesize - (pending.bytesize % size)
      return if whole.zero?

      Primitive.zr_digest_blocks(metadata.algorithm, state, pending.byteslice(0, whole))
      pending.replace(pending.byteslice(whole, pending.bytesize - whole))
    end
  end
end
