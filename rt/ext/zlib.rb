# frozen_string_literal: true

# zlib.c, in ruby, over zr's port of zlib (rt/kernel/zlib_*.rb, reached
# through rt/kernel/zlib.rb). The extension's structs are classes here: Stream
# is `struct zstream`, the z_stream and the buffers around it, and
# GzFile is `struct gzfile`, a stream and the gzip container's fields. A Deflate, an Inflate or a GzipFile holds its own
# in a hidden slot, as a TypedData object holds its struct.
module Zlib
  VERSION = "3.2.3"
  ZLIB_VERSION = "1.3.1"

  class Error < StandardError; end
  class StreamEnd < Error; end
  class NeedDict < Error; end
  class DataError < Error; end
  class StreamError < Error; end
  class MemError < Error; end
  class BufError < Error; end
  class VersionError < Error; end
  class InProgressError < Error; end

  BINARY = 0
  ASCII = 1
  TEXT = 1
  UNKNOWN = 2
  NO_COMPRESSION = 0
  BEST_SPEED = 1
  BEST_COMPRESSION = 9
  DEFAULT_COMPRESSION = -1
  FILTERED = 1
  HUFFMAN_ONLY = 2
  RLE = 3
  FIXED = 4
  DEFAULT_STRATEGY = 0
  MAX_WBITS = 15
  DEF_MEM_LEVEL = 8
  MAX_MEM_LEVEL = 9
  NO_FLUSH = 0
  SYNC_FLUSH = 2
  FULL_FLUSH = 3
  FINISH = 4
  OS_CODE = 3
  OS_MSDOS = 0
  OS_AMIGA = 1
  OS_VMS = 2
  OS_UNIX = 3
  OS_VMCMS = 4
  OS_ATARI = 5
  OS_OS2 = 6
  OS_MACOS = 7
  OS_ZSYSTEM = 8
  OS_CPM = 9
  OS_TOPS20 = 10
  OS_WIN32 = 11
  OS_QDOS = 12
  OS_RISCOS = 13
  OS_UNKNOWN = 255

  # zlib's return codes.
  Z_OK = 0
  Z_STREAM_END = 1
  Z_NEED_DICT = 2
  Z_ERRNO = -1
  Z_STREAM_ERROR = -2
  Z_DATA_ERROR = -3
  Z_MEM_ERROR = -4
  Z_BUF_ERROR = -5
  Z_VERSION_ERROR = -6
  ERRORS = { Z_STREAM_END => StreamEnd, Z_NEED_DICT => NeedDict, Z_STREAM_ERROR => StreamError, Z_DATA_ERROR => DataError,
             Z_BUF_ERROR => BufError, Z_VERSION_ERROR => VersionError, Z_MEM_ERROR => MemError }.freeze
  CRC = 0
  ADLER = 1
  private_constant :Z_OK, :Z_STREAM_END, :Z_NEED_DICT, :Z_ERRNO, :Z_STREAM_ERROR, :Z_DATA_ERROR, :Z_MEM_ERROR,
                   :Z_BUF_ERROR, :Z_VERSION_ERROR, :ERRORS, :CRC, :ADLER

  class << self
    def deflate(*args, &block)
      Deflate.send(:deflated, *args, &block)
    end

    def inflate(src, &block)
      Inflate.send(:inflated, src, &block)
    end

    # zlib_s_gzip: one gzip member of `src`, header and footer included.
    def gzip(*args, &block)
      opts = args.size > 0 ? Hash.try_convert(args.last) : nil
      args.pop if opts
      level, strategy = Zlib.send(:keywords, opts, :level, :strategy)
      raise ArgumentError, "wrong number of arguments (given #{args.size}, expected 1)" unless args.size == 1

      src = Primitive.zr_str_operand(args[0])
      gz = GzFile.new(:gzip)
      gz.level = Zlib.send(:level_arg, level)
      err = gz.z.init(gz.level, -MAX_WBITS, DEF_MEM_LEVEL, Zlib.send(:strategy_arg, strategy))
      unless err == Z_OK
        gz.finish
        Zlib.send(:raise_error, err, gz.z.message)
      end
      gz.z.ready
      begin
        gz.make_header
        unless src.empty?
          gz.crc = Zlib.send(:checksum_of, CRC, gz.crc, src)
          gz.z.run(src, NO_FLUSH, nil)
        end
        gz.close(false)
        gz.z.detach_buffer(nil)
      ensure
        begin
          gz.finish
        rescue StandardError
          nil
        end
        gz.z.release
      end
    end

    # zlib_gunzip: the one member `src` holds, its footer checked.
    def gunzip(src)
      src = Primitive.zr_str_operand(src)
      gz = GzFile.new(:gunzip)
      err = gz.z.init(0, -MAX_WBITS, 0, 0)
      Zlib.send(:raise_error, err, gz.z.message) unless err == Z_OK
      gz.io = GzFile::STRING
      gz.z.lend_input(src)
      gz.z.ready
      begin
        gz.read_header(nil)
        dst = gz.z.detach_buffer(nil)
        gz.calc_crc(dst)
        raise GzipFile::Error, "unexpected end of file" unless gz.z.finished?
        raise GzipFile::NoFooter, "footer is not found" if gz.z.input.nil?

        gz.check_footer(nil)
        dst
      ensure
        begin
          gz.finish
        rescue StandardError
          nil
        end
        gz.z.release
      end
    end

    private

    # raise_zlib_error: the error class a return code names, with zlib's
    # message or the code's own words.
    def raise_error(err, message)
      Primitive.attr! :hidden
      message ||= Primitive.zr_zlib_message(err)
      raise SystemCallError.new(message) if err == Z_ERRNO

      klass = ERRORS[err]
      raise klass, message if klass

      raise Error, "unknown zlib error #{err}: #{message}"
    end

    # do_checksum: `str`, or an IO read to its end, onto `sum`.
    def checksum(args, kind)
      Primitive.attr! :hidden
      raise ArgumentError, "wrong number of arguments (given #{args.size}, expected 0..2)" if args.size > 2

      str, vsum = args
      sum = if !vsum.nil? then unsigned(vsum)
            elsif str.nil? then 0
            else Primitive.zr_zlib_checksum(kind, 0, nil)
            end
      if str.nil?
        sum = Primitive.zr_zlib_checksum(kind, sum & 0xffff_ffff, nil)
      elsif str.is_a?(IO)
        while (buf = str.read(8192))
          sum = checksum_of(kind, sum, Primitive.zr_str_operand(buf))
        end
      else
        sum = checksum_of(kind, sum, Primitive.zr_str_operand(str))
      end
      sum
    end

    def checksum_of(kind, sum, str)
      Primitive.attr! :hidden
      Primitive.zr_zlib_checksum(kind, sum & 0xffff_ffff, str)
    end

    # NUM2ULONG: an Integer, or its to_int, as an unsigned long.
    def unsigned(v)
      Primitive.attr! :hidden
      n = v.is_a?(Integer) ? v : Primitive.zr_index_operand_m(v)
      raise RangeError, "bignum too big to convert into 'unsigned long'" unless n.between?(-0xffff_ffff_ffff_ffff, 0xffff_ffff_ffff_ffff)

      n & 0xffff_ffff_ffff_ffff
    end

    # NUM2INT, which a FIXNUMARG reads as.
    def int(v)
      Primitive.attr! :hidden
      n = v.is_a?(Integer) ? v : Primitive.zr_index_operand_m(v)
      raise RangeError, "integer #{n} too big to convert to 'int'" if n > 0x7fff_ffff
      raise RangeError, "integer #{n} too small to convert to 'int'" if n < -0x8000_0000

      n
    end

    def level_arg(v) = v.nil? ? DEFAULT_COMPRESSION : int(v)
    def wbits_arg(v) = v.nil? ? MAX_WBITS : int(v)
    def memlevel_arg(v) = v.nil? ? DEF_MEM_LEVEL : int(v)
    def strategy_arg(v) = v.nil? ? DEFAULT_STRATEGY : int(v)
    def flush_arg(v, default = NO_FLUSH) = v.nil? ? default : int(v)

    # rb_get_kwargs over an options hash that may name only `names`.
    def keywords(opts, *names)
      Primitive.attr! :hidden
      return [] if opts.nil?

      unknown = opts.keys - names
      unless unknown.empty?
        raise ArgumentError, "unknown keyword#{'s' if unknown.size > 1}: #{unknown.map(&:inspect).join(', ')}"
      end

      names.map { |name| opts[name] }
    end

    # rb_str_cat: `bytes` onto the end of `str`, whatever either's
    # encoding, which `str` keeps.
    def cat(str, bytes)
      Primitive.attr! :hidden
      encoding = str.encoding
      str.force_encoding(Encoding::BINARY) << bytes.b
      str.force_encoding(encoding)
    end

    # rb_str_resize and a copy: `str` holds `bytes` and keeps its encoding.
    def fill_in(str, bytes)
      Primitive.attr! :hidden
      encoding = str.encoding
      str.replace(bytes)
      str.force_encoding(encoding)
    end
  end

  def zlib_version = Primitive.zr_zlib_version

  def adler32(*args) = Zlib.send(:checksum, args, ADLER)

  def adler32_combine(adler1, adler2, len2)
    Primitive.zr_zlib_combine(ADLER, Zlib.send(:unsigned, adler1) & 0xffff_ffff, Zlib.send(:unsigned, adler2) & 0xffff_ffff, Primitive.zr_index_operand_m(len2))
  end

  def crc32(*args) = Zlib.send(:checksum, args, CRC)

  def crc32_combine(crc1, crc2, len2)
    Primitive.zr_zlib_combine(CRC, Zlib.send(:unsigned, crc1) & 0xffff_ffff, Zlib.send(:unsigned, crc2) & 0xffff_ffff, Primitive.zr_index_operand_m(len2))
  end

  def crc_table = Primitive.zr_zlib_crc_table.unpack("V256")

  module_function :zlib_version, :adler32, :adler32_combine, :crc32, :crc32_combine, :crc_table

  # struct zstream.
  class Stream
    Primitive.attr! :hidden

    READY = 1 << 0
    IN_STREAM = 1 << 1
    FINISHED = 1 << 2
    CLOSING = 1 << 3
    GZFILE = 1 << 4
    REUSE_BUFFER = 1 << 5
    IN_PROGRESS = 1 << 6
    UNUSED = 1 << 7

    INITIAL_BUFSIZE = 1024
    # The most a String holds inside its own slot.
    EMBED_MAX = 615
    AVAIL_OUT_STEP_MAX = 16384
    AVAIL_OUT_STEP_MIN = 2048

    # What rt/kernel/zlib.rb runs.
    DEFLATE = 0
    INFLATE = 1
    DEFLATE_END = 2
    INFLATE_END = 3
    DEFLATE_RESET = 4
    INFLATE_RESET = 5
    INFLATE_SYNC = 6
    INFLATE_SYNC_POINT = 7

    attr_accessor :flags, :avail_out, :capa
    attr_reader :buf, :input, :kind, :mutex

    # A stream `holder` owns frees its z_stream once the holder is
    # gone, as the extension's free function does; `opaque` is the
    # object zlib.c's z_stream names, which keeps the dictionaries.
    def initialize(kind, holder: nil, opaque: nil)
      @kind = kind
      @opaque = opaque
      @flags = 0
      @buf = nil
      @capa = 0
      @shared = false
      @input = nil
      @input_hidden = false
      @avail_out = 0
      @mutex = Thread::Mutex.new
      @stream = Primitive.zr_zlib_new
      ObjectSpace.define_finalizer(holder, Stream.release(@stream, kind)) if holder
    end

    def self.release(stream, kind) = proc { Primitive.zr_zlib_release(stream, kind) }

    def release = Primitive.zr_zlib_release(@stream, @kind)

    def init(level, wbits, memlevel, strategy) = Primitive.zr_zlib_init(@stream, @kind, level, wbits, memlevel, strategy)

    def ready = @flags |= READY
    def ready? = @flags.anybits?(READY)
    def finished? = @flags.anybits?(FINISHED)
    def closing? = @flags.anybits?(CLOSING)
    def gzfile? = @flags.anybits?(GZFILE)
    def reuse_buffer? = @flags.anybits?(REUSE_BUFFER)
    def deflate? = @kind == DEFLATE

    def buf_filled = @buf.nil? ? 0 : @buf.bytesize

    # [avail_in, total_in, avail_out, total_out, data_type, adler, msg]
    def fields = Primitive.zr_zlib_fields(@stream)
    def avail_in = fields[0]
    def total_in = fields[1]
    def total_out = fields[3]
    def data_type = fields[4]
    def adler = fields[5]
    def message = fields[6]

    def count_in(n) = Primitive.zr_zlib_count_in(@stream, n)

    def copy_from(other)
      err = Primitive.zr_zlib_copy(@stream, other.stream)
      Zlib.send(:raise_error, err, nil) unless err == Z_OK

      @input = other.input&.dup
      @input_hidden = true
      @buf = other.buf&.dup
      # rb_str_dup shares a buffer too big to embed, and a shared String
      # holds no room past its end and takes no new length.
      @shared = !@buf.nil? && other.capa > EMBED_MAX
      @capa = @shared ? buf_filled : other.capa
      @avail_out = other.avail_out
      @flags = other.flags
    end

    # The buffer a stream reads out of and writes into by itself; a
    # user's String for Inflate#inflate's `buffer:`.
    def buf=(str)
      @buf = str
      @shared = false
    end

    def call(op, flush = 0) = Primitive.zr_zlib_call(@stream, op, flush, nil, 0)

    def expand_buffer(block)
      return expand_buffer_into(INITIAL_BUFSIZE) if @buf.nil?

      if !gzfile? && block
        filled = buf_filled
        if filled >= AVAIL_OUT_STEP_MAX
          out = @buf
          begin
            block.call(out)
          ensure
            if reuse_buffer?
              @buf.clear
              @shared = false
            else
              self.buf = nil
            end
            expand_buffer_into(AVAIL_OUT_STEP_MAX)
          end
        else
          expand_buffer_into(AVAIL_OUT_STEP_MAX - filled)
        end
      else
        expand_buffer_non_stream
      end
    end

    def expand_buffer_into(size)
      if @buf.nil?
        @buf = String.new(capacity: size, encoding: Encoding::BINARY)
        @capa = size
        @avail_out = size
      elsif @avail_out != size
        expand(size)
        @avail_out = size
      end
    end

    def expand_buffer_non_stream
      len = buf_filled
      if @capa - len >= AVAIL_OUT_STEP_MAX
        @avail_out = AVAIL_OUT_STEP_MAX
      else
        inc = [len / 2, AVAIL_OUT_STEP_MIN].max
        expand(inc)
        @avail_out = [inc, AVAIL_OUT_STEP_MAX].min
      end
    end

    # rb_str_modify_expand: room for `n` more bytes past the end.
    def expand(n)
      @capa = [@capa, buf_filled + n].max
      @shared = false
    end

    # rb_str_set_len, which a shared buffer refuses.
    def settable
      raise RuntimeError, "can't set length of shared string" if @shared
    end

    def append_buffer(bytes)
      if @buf.nil?
        @buf = bytes.b
        @capa = bytes.bytesize
        @avail_out = 0
        return
      end

      if @capa < buf_filled + bytes.bytesize
        expand(bytes.bytesize)
        @avail_out = 0
      else
        @avail_out = @avail_out >= bytes.bytesize ? @avail_out - bytes.bytesize : 0
      end
      @shared = false
      Zlib.send(:cat, @buf, bytes)
    end

    def detach_buffer(block)
      return nil if !finished? && !gzfile? && block

      dst = @buf || "".b
      self.buf = nil
      @avail_out = 0
      return dst unless !gzfile? && block

      block.call(dst)
      nil
    end

    def shift_buffer(len, dst, block = nil)
      filled = buf_filled
      if filled <= len
        return detach_buffer(block) if dst.nil? || (!finished? && !gzfile? && block)

        Zlib.send(:fill_in, dst, @buf)
        settable
        @buf.clear
      else
        head = @buf.byteslice(0, len)
        if dst.nil?
          dst = head
        else
          Zlib.send(:fill_in, dst, head)
        end
        settable
        @buf.replace(@buf.byteslice(len, filled - len))
      end
      @avail_out = [@capa - buf_filled, AVAIL_OUT_STEP_MAX].min
      dst
    end

    def buffer_ungets(bytes)
      len = bytes.bytesize
      expand_buffer_into(len)
      settable
      @buf.prepend(bytes.b)
      @avail_out -= [len, @avail_out].min if @avail_out > 0
    end

    def append_input(bytes)
      return if bytes.nil? || bytes.empty?

      if @input.nil?
        @input = bytes.b
        @input_hidden = true
      else
        Zlib.send(:cat, @input, bytes)
      end
    end

    # gunzip reads the caller's own String, which it never changes.
    def lend_input(str)
      @input = str
      @input_hidden = false
    end

    def discard_input(len)
      return if @input.nil?

      if @input_hidden
        rest = @input.bytesize - len
        if rest <= 0
          @input = nil
        else
          @input.replace(@input.byteslice(len, rest))
        end
      elsif @input.bytesize <= len
        @input = nil
      else
        @input = @input.byteslice(len, @input.bytesize - len)
        @input_hidden = true
      end
    end

    def reset_input
      if @input && @input_hidden
        @input.clear
      else
        @input = nil
      end
    end

    def passthrough_input
      return if @input.nil?

      append_buffer(@input)
      @input = nil
    end

    def detach_input
      dst = @input || "".b
      @input = nil
      dst
    end

    def reset
      err = call(deflate? ? DEFLATE_RESET : INFLATE_RESET)
      Zlib.send(:raise_error, err, message) unless err == Z_OK

      @flags = READY
      self.buf = nil
      @avail_out = 0
      reset_input
    end

    def end_stream
      unless ready?
        warning("attempt to close uninitialized zstream; ignored.")
        return nil
      end
      if @flags.anybits?(IN_STREAM)
        warning("attempt to close unfinished zstream; reset forced.")
        reset
      end

      reset_input
      err = call(deflate? ? DEFLATE_END : INFLATE_END)
      Zlib.send(:raise_error, err, message) unless err == Z_OK

      @flags = 0
      nil
    end

    def dictionary(dic)
      src = Primitive.zr_str_operand(dic)
      err = Primitive.zr_zlib_dictionary(@stream, @kind, src)
      Zlib.send(:raise_error, err, message) unless err == Z_OK

      dic
    end

    # deflateParams, flushing what the old parameters left pending.
    def params(level, strategy)
      err = Primitive.zr_zlib_params(@stream, level, strategy, @buf, @avail_out)
      @avail_out = fields[2] unless @buf.nil?
      while err == Z_BUF_ERROR
        warning("deflateParams() returned Z_BUF_ERROR")
        expand_buffer(nil)
        err = Primitive.zr_zlib_params(@stream, level, strategy, @buf, @avail_out)
        @avail_out = fields[2]
      end
      Zlib.send(:raise_error, err, message) unless err == Z_OK

      settable
    end

    def sync_point?
      err = call(INFLATE_SYNC_POINT)
      return true if err == 1

      Zlib.send(:raise_error, err, message) unless err == Z_OK
      false
    end

    # zstream_run: `src` and the input kept from before through zlib with
    # `flush`, the output into the buffer. A block given to the method
    # that runs takes the output as it fills, a buffer at a time.
    def run(src, flush, block)
      raise InProgressError, "zlib stream is in progress" if @flags.anybits?(IN_PROGRESS)

      @flags |= IN_PROGRESS
      begin
        run_try(src, flush, !gzfile? && block)
      ensure
        @flags &= ~IN_PROGRESS
      end
    end

    def sync(src)
      if @input
        Primitive.zr_zlib_input(@stream, @input, 0)
        err = call(INFLATE_SYNC)
        if err == Z_OK
          discard_input(@input.bytesize - avail_in)
          append_input(src)
          return true
        end
        reset_input
        Zlib.send(:raise_error, err, message) unless err == Z_DATA_ERROR
      end
      return false if src.empty?

      Primitive.zr_zlib_input(@stream, src, 0)
      err = call(INFLATE_SYNC)
      if err == Z_OK
        left = avail_in
        append_input(src.byteslice(src.bytesize - left, left))
        return true
      end
      Zlib.send(:raise_error, err, message) unless err == Z_DATA_ERROR
      false
    end

    protected

    attr_reader :stream

    private

    def run_try(src, flush, block)
      if @input.nil? && src.empty?
        source = nil
      else
        append_input(src)
        source = detach_input
      end
      Primitive.zr_zlib_input(@stream, source, 0)
      expand_buffer(block) if @avail_out.zero?

      while settle(source, run_func(source, flush, block), flush)
      end
    end

    # What follows one pass of zlib: the input it left kept for the
    # next run, and an error raised. Answers true when a dictionary the
    # stream asked for was set and the pass runs again.
    def settle(source, err, flush)
      left = avail_in
      @flags |= IN_STREAM if flush != FINISH && err == Z_BUF_ERROR && @avail_out > 0
      reset_input
      rest = source.byteslice(source.bytesize - left, left) if left > 0
      if err != Z_OK && err != Z_STREAM_END
        append_input(rest)
        if err == Z_NEED_DICT && @opaque
          dict = @opaque.instance_variable_get(:@dictionaries)[adler]
          if dict
            dictionary(dict)
            return true
          end
        end
        Zlib.send(:raise_error, err, message)
      end
      append_input(rest)
      false
    end

    def run_func(source, flush, block)
      while true
        filled = buf_filled
        err = Primitive.zr_zlib_call(@stream, @kind, flush, @buf, @avail_out)
        left, _, @avail_out = fields
        if @shared
          @buf.replace(@buf.byteslice(0, filled))
          settable
        end

        if err == Z_STREAM_END
          @flags &= ~IN_STREAM
          @flags |= FINISHED
          return err
        end
        return err if err != Z_OK && err != Z_BUF_ERROR

        if @avail_out > 0 || (left.zero? && !deflate?)
          @flags |= IN_STREAM
          return err
        end

        if block
          # A block that breaks out or raises as the buffer fills leaves
          # the stream as a finished pass would, and the jump goes on.
          jumped = true
          begin
            expand_buffer(block)
            jumped = false
          ensure
            settle(source, Z_OK, flush) if jumped
          end
        else
          expand_buffer_non_stream
        end
      end
    end

    def warning(message)
      Warning.warn("#{Primitive.zr_warn_position}warning: #{message}\n") if $VERBOSE
    end
  end
  private_constant :Stream

  class ZStream
    Primitive.zr_undef_allocator(self)

    def avail_out = zstream.avail_out

    def avail_out=(size)
      ready_zstream.expand_buffer_into(Zlib.send(:int, size))
      size
    end

    def avail_in = zstream.input&.bytesize || 0

    def total_in = ready_zstream.total_in

    def total_out = ready_zstream.total_out

    def data_type = ready_zstream.data_type

    def adler = ready_zstream.adler

    def finished? = ready_zstream.finished?

    def stream_end? = ready_zstream.finished?

    def closed? = !zstream.ready?

    def ended? = !zstream.ready?

    def close
      ready_zstream.end_stream
      nil
    end

    def end
      ready_zstream.end_stream
      nil
    end

    def reset
      ready_zstream.reset
      nil
    end

    def finish(&block)
      z = ready_zstream
      z.run("", FINISH, block)
      z.detach_buffer(block)
    end

    def flush_next_in = zstream.detach_input

    def flush_next_out(&block) = zstream.detach_buffer(block)

    private

    # A copy starts with a stream of its own, which no call has made
    # ready, as the one its allocator made.
    def initialize_copy(orig)
      Primitive.attr! :hidden
      Primitive.zr_state_set(self, :__zstream__, nil)
      Kernel.instance_method(:initialize_copy).bind_call(self, orig)
    end

    def zstream
      Primitive.attr! :hidden
      Primitive.zr_hidden_get(self, :__zstream__) ||
        Primitive.zr_state_set(self, :__zstream__, Stream.new(stream_kind, holder: self, opaque: self))
    end

    # get_zstream: the stream, once initialize made it ready.
    def ready_zstream
      Primitive.attr! :hidden
      z = zstream
      raise Error, "stream is not ready" unless z.ready?

      z
    end

    # rb_mutex_synchronize over the stream's own lock.
    def exclusively(z)
      Primitive.attr! :hidden
      z.mutex.lock
      begin
        yield
      ensure
        z.mutex.unlock
      end
    end
  end

  class Deflate < ZStream
    Primitive.zr_define_alloc(self)

    def self.deflate(*args, &block)
      deflated(*args, &block)
    end

    def self.deflated(src, level = nil, &block)
      Primitive.attr! :hidden
      lev = Zlib.send(:level_arg, level)
      src = Primitive.zr_str_operand(src)
      z = Stream.new(Stream::DEFLATE)
      err = z.init(lev, MAX_WBITS, DEF_MEM_LEVEL, DEFAULT_STRATEGY)
      unless err == Z_OK
        message = z.message
        z.release
        Zlib.send(:raise_error, err, message)
      end
      z.ready
      begin
        z.run(src, FINISH, block)
        z.detach_buffer(block)
      ensure
        begin
          z.end_stream
        ensure
          z.release
        end
      end
    end
    private_class_method :deflated

    def initialize(level = nil, wbits = nil, memlevel = nil, strategy = nil)
      z = zstream
      err = z.init(Zlib.send(:level_arg, level), Zlib.send(:wbits_arg, wbits), Zlib.send(:memlevel_arg, memlevel), Zlib.send(:strategy_arg, strategy))
      Zlib.send(:raise_error, err, z.message) unless err == Z_OK

      z.ready
      self
    end

    def initialize_copy(orig)
      z2 = orig.send(:ready_zstream)
      return self if equal?(orig)

      z1 = Stream.new(Stream::DEFLATE, holder: self, opaque: self)
      Primitive.zr_state_set(self, :__zstream__, z1)
      z1.copy_from(z2)
      self
    end

    def deflate(src, flush = nil, &block)
      z = ready_zstream
      exclusively(z) do
        run_deflate(z, src, Zlib.send(:flush_arg, flush), block)
        z.detach_buffer(block)
      end
    end

    def <<(src)
      run_deflate(ready_zstream, src, NO_FLUSH, nil)
      self
    end

    def flush(flush = nil, &block)
      z = ready_zstream
      flush = Zlib.send(:flush_arg, flush, SYNC_FLUSH)
      z.run("", flush, block) unless flush == NO_FLUSH
      z.detach_buffer(block)
    end

    def params(level, strategy)
      ready_zstream.params(Zlib.send(:level_arg, level), Zlib.send(:strategy_arg, strategy))
      nil
    end

    def set_dictionary(dic) = ready_zstream.dictionary(dic)

    private

    def stream_kind
      Primitive.attr! :hidden
      Stream::DEFLATE
    end

    # do_deflate: nil finishes the stream; an empty String with no flush
    # runs nothing, since zlib would answer Z_BUF_ERROR.
    def run_deflate(z, src, flush, block)
      Primitive.attr! :hidden
      return z.run("", FINISH, block) if src.nil?

      src = Primitive.zr_str_operand(src)
      z.run(src, flush, block) if flush != NO_FLUSH || !src.empty?
    end
  end

  class Inflate < ZStream
    Primitive.zr_define_alloc(self)

    class << self
      # rb_inflate_s_allocate: a stream, and the dictionaries it may ask for.
      def allocate
        Primitive.attr! :hidden
        inflate = Primitive.zr_class_build(self)
        inflate.instance_variable_set(:@dictionaries, {})
        inflate
      end

      def new(*args, &block)
        Primitive.attr! :hidden
        inflate = allocate
        inflate.__send__(:initialize, *args, &block)
        inflate
      end

      def inflate(src, &block)
        inflated(src, &block)
      end

      private

      def inflated(src, &block)
        Primitive.attr! :hidden
        src = Primitive.zr_str_operand(src)
        z = Stream.new(Stream::INFLATE)
        err = z.init(0, MAX_WBITS, 0, 0)
        unless err == Z_OK
          message = z.message
          z.release
          Zlib.send(:raise_error, err, message)
        end
        z.ready
        begin
          z.run(src, SYNC_FLUSH, block)
          z.run("", FINISH, block)
          z.detach_buffer(block)
        ensure
          begin
            z.end_stream
          ensure
            z.release
          end
        end
      end
    end

    def initialize(wbits = nil)
      z = zstream
      err = z.init(0, Zlib.send(:wbits_arg, wbits), 0, 0)
      Zlib.send(:raise_error, err, z.message) unless err == Z_OK

      z.ready
      self
    end

    def add_dictionary(dictionary)
      @dictionaries[Zlib.adler32(dictionary)] = dictionary
      self
    end

    def inflate(*args, &block)
      z = ready_zstream
      exclusively(z) do
        opts = args.size > 0 ? Hash.try_convert(args.last) : nil
        args.pop if opts
        buffer, = Zlib.send(:keywords, opts, :buffer)
        buffer = Primitive.zr_str_operand(buffer) unless buffer.nil?
        if buffer
          unless z.reuse_buffer? && z.buf.equal?(buffer)
            z.capa = [buffer.bytesize, Stream::AVAIL_OUT_STEP_MAX].max
            buffer.clear
            z.flags |= Stream::REUSE_BUFFER
            z.buf = buffer
          end
        elsif z.reuse_buffer?
          z.flags &= ~Stream::REUSE_BUFFER
          z.buf = nil
        end
        raise ArgumentError, "wrong number of arguments (given #{args.size}, expected 1)" unless args.size == 1

        src = args[0]
        if z.finished?
          if src.nil?
            z.detach_buffer(block)
          else
            z.append_buffer(Primitive.zr_str_operand(src))
            z.reuse_buffer? ? buffer.clear : "".b
          end
        else
          run_inflate(z, src, block)
          dst = z.detach_buffer(block)
          z.passthrough_input if z.finished?
          dst
        end
      end
    end

    def <<(src)
      z = ready_zstream
      if z.finished?
        z.append_buffer(Primitive.zr_str_operand(src)) unless src.nil?
      else
        run_inflate(z, src, nil)
        z.passthrough_input if z.finished?
      end
      self
    end

    def sync(src) = ready_zstream.sync(Primitive.zr_str_operand(src))

    def sync_point? = ready_zstream.sync_point?

    def set_dictionary(dic) = ready_zstream.dictionary(dic)

    private

    def stream_kind
      Primitive.attr! :hidden
      Stream::INFLATE
    end

    # do_inflate: nil finishes the stream; nothing to read runs nothing.
    def run_inflate(z, src, block)
      Primitive.attr! :hidden
      return z.run("", FINISH, block) if src.nil?

      src = Primitive.zr_str_operand(src)
      z.run(src, SYNC_FLUSH, block) if !src.empty? || z.avail_in > 0
    end
  end

  class GzipFile
    # gzfile_raise sets `@input` where a program sees it.
    class Error < Zlib::Error
      def input = Primitive.zr_hidden_get(self, :@input)

      def inspect
        str = super
        return str if input.nil?

        "#{str.chop}, input=#{input.inspect}>"
      end
    end

    class NoFooter < Error; end
    class CRCError < Error; end
    class LengthError < Error; end

  end

  # struct gzfile.
  class GzFile
    Primitive.attr! :hidden

    MAGIC1 = 0x1f
    MAGIC2 = 0x8b
    METHOD_DEFLATE = 8
    FLAG_MULTIPART = 0x2
    FLAG_EXTRA = 0x4
    FLAG_ORIG_NAME = 0x8
    FLAG_COMMENT = 0x10
    FLAG_ENCRYPT = 0x20
    FLAG_UNKNOWN_MASK = 0xc0
    EXTRAFLAG_FAST = 0x4
    EXTRAFLAG_SLOW = 0x2

    FLAG_SYNC = Stream::UNUSED
    FLAG_HEADER_FINISHED = Stream::UNUSED << 1
    FLAG_FOOTER_FINISHED = Stream::UNUSED << 2
    FLAG_MTIME_IS_SET = Stream::UNUSED << 3

    READ_SIZE = 2048

    # The io of Zlib.gunzip, which reads a String it already holds.
    STRING = Object.new.freeze

    # The most bytes one character takes, which a read that must not
    # split one looks ahead by.
    MBMAXLEN = { "UTF-8" => 4, "EUC-JP" => 3, "Shift_JIS" => 2, "Windows-31J" => 2, "GBK" => 2, "GB18030" => 4,
                 "Big5" => 2, "EUC-KR" => 2, "UTF-16LE" => 4, "UTF-16BE" => 4, "UTF-32LE" => 4, "UTF-32BE" => 4 }.freeze

    attr_accessor :io, :level, :os_code, :mtime, :orig_name, :comment, :crc, :lineno, :ungetc, :path, :enc, :enc2
    attr_reader :z

    def initialize(ending, holder: nil)
      kind = %i[writer gzip].include?(ending) ? Stream::DEFLATE : Stream::INFLATE
      @z = Stream.new(kind, holder: holder)
      @z.flags |= Stream::GZFILE
      @ending = ending
      @io = nil
      @level = 0
      @mtime = 0
      @os_code = OS_CODE
      @orig_name = nil
      @comment = nil
      @crc = 0
      @lineno = 0
      @ungetc = 0
      @enc = Encoding.default_external
      @enc2 = nil
      @ecopts = nil
      @path = nil
    end

    def flag?(flag) = @z.flags.anybits?(flag)
    def flag(flag) = @z.flags |= flag

    def finished? = @z.finished? && @z.buf_filled.zero?

    def reset
      @z.reset
      flag(Stream::GZFILE)
      @crc = 0
      @lineno = 0
      @ungetc = 0
    end

    def close(close_io)
      io = @io
      finish
      @io = nil
      @orig_name = nil
      @comment = nil
      io.close if close_io && io.respond_to?(:close)
    end

    # gz->end: each kind of file ends its stream its own way.
    def finish
      case @ending
      when :writer then writer_end
      when :reader then reader_end
      when :gzip
        flag(Stream::CLOSING)
        @z.run("", FINISH, nil)
        make_footer
        @z.end_stream
      when :gunzip
        flag(Stream::CLOSING)
        @z.end_stream
      end
    end

    def write_raw
      return unless @z.buf_filled > 0

      @io.write(@z.detach_buffer(nil))
      @io.flush if flag?(FLAG_SYNC) && @io.respond_to?(:flush)
    end

    # gzfile_read_raw: a readpartial of the io, or its read where it has
    # none; nil at the end.
    def read_raw(outbuf)
      args = outbuf.nil? ? [READ_SIZE] : [READ_SIZE, outbuf]
      begin
        string_of(@io.readpartial(*args))
      rescue EOFError
        nil
      rescue NoMethodError
        str = @io.read(*args)
        str.nil? ? nil : string_of(str)
      end
    end

    def read_raw_ensure(size, outbuf)
      if @io.equal?(STRING) && (@z.input.nil? || @z.input.bytesize < size)
        raise GzipFile::Error, "unexpected end of string"
      end

      while @z.input.nil? || @z.input.bytesize < size
        str = read_raw(outbuf)
        return false if str.nil?

        @z.append_input(str)
      end
      true
    end

    def read_raw_until_zero(offset)
      while true
        at = @z.input.byteindex("\0", offset)
        return at if at

        str = read_raw(nil)
        raise GzipFile::Error, "unexpected end of file" if str.nil?

        offset = @z.input.bytesize
        @z.append_input(str)
      end
    end

    # gzfile_raise: the error, and the input not yet read where there is
    # some.
    def raise_input(klass, message)
      error = klass.new(message)
      error.instance_variable_set(:@input, String.new(@z.input)) unless @z.input.nil?
      raise error
    end

    def make_header
      flags = 0
      flags |= FLAG_ORIG_NAME unless @orig_name.nil?
      flags |= FLAG_COMMENT unless @comment.nil?
      @mtime = Time.now.to_i unless flag?(FLAG_MTIME_IS_SET)
      extra = if @level == BEST_SPEED then EXTRAFLAG_FAST
              elsif @level == BEST_COMPRESSION then EXTRAFLAG_SLOW
              else 0
              end
      @z.append_buffer([MAGIC1, MAGIC2, METHOD_DEFLATE, flags, @mtime & 0xffff_ffff, extra, @os_code & 0xff].pack("C4VC2"))
      @z.append_buffer("#{@orig_name.b}\0") unless @orig_name.nil?
      @z.append_buffer("#{@comment.b}\0") unless @comment.nil?
      flag(FLAG_HEADER_FINISHED)
    end

    def make_footer
      @z.append_buffer([@crc, @z.total_in & 0xffff_ffff].pack("VV"))
      flag(FLAG_FOOTER_FINISHED)
    end

    def read_header(outbuf)
      raise_input(GzipFile::Error, "not in gzip format") unless read_raw_ensure(10, outbuf)

      head = @z.input.byteslice(0, 10).bytes
      raise_input(GzipFile::Error, "not in gzip format") if head[0] != MAGIC1 || head[1] != MAGIC2
      raise GzipFile::Error, "unsupported compression method #{head[2]}" if head[2] != METHOD_DEFLATE

      flags = head[3]
      if flags.anybits?(FLAG_MULTIPART)
        raise GzipFile::Error, "multi-part gzip file is not supported"
      elsif flags.anybits?(FLAG_ENCRYPT)
        raise GzipFile::Error, "encrypted gzip file is not supported"
      elsif flags.anybits?(FLAG_UNKNOWN_MASK)
        # A char, which the format widens as an int.
        raise GzipFile::Error, format("unknown flags 0x%02x", flags >= 0x80 ? flags | 0xffff_ff00 : flags)
      end

      @level = if head[8].anybits?(EXTRAFLAG_FAST) then BEST_SPEED
               elsif head[8].anybits?(EXTRAFLAG_SLOW) then BEST_COMPRESSION
               else DEFAULT_COMPRESSION
               end
      @mtime = @z.input.byteslice(4, 4).unpack1("V")
      @os_code = head[9]
      @z.discard_input(10)

      if flags.anybits?(FLAG_EXTRA)
        raise GzipFile::Error, "unexpected end of file" unless read_raw_ensure(2, outbuf)

        len = @z.input.byteslice(0, 2).unpack1("v")
        raise GzipFile::Error, "unexpected end of file" unless read_raw_ensure(2 + len, outbuf)

        @z.discard_input(2 + len)
      end
      @orig_name = read_zero_terminated(outbuf) if flags.anybits?(FLAG_ORIG_NAME)
      @comment = read_zero_terminated(outbuf) if flags.anybits?(FLAG_COMMENT)

      @z.run("", SYNC_FLUSH, nil) if @z.input && !@z.input.empty?
    end

    def check_footer(outbuf)
      flag(FLAG_FOOTER_FINISHED)
      raise_input(GzipFile::NoFooter, "footer is not found") unless read_raw_ensure(8, outbuf)

      crc, length = @z.input.byteslice(0, 8).unpack("VV")
      @z.count_in(8)
      @z.discard_input(8)
      raise GzipFile::CRCError, "invalid compressed data -- crc error" if @crc != crc
      raise GzipFile::LengthError, "invalid compressed data -- length error" if @z.total_out & 0xffff_ffff != length
    end

    def write(str)
      make_header unless flag?(FLAG_HEADER_FINISHED)
      if !str.empty? || flag?(FLAG_SYNC)
        @crc = Zlib.send(:checksum_of, CRC, @crc, str)
        @z.run(str, flag?(FLAG_SYNC) ? SYNC_FLUSH : NO_FLUSH, nil)
      end
      write_raw
    end

    def read_more(outbuf)
      until @z.finished?
        str = read_raw(outbuf)
        if str.nil?
          raise GzipFile::Error, "unexpected end of file" unless @z.finished?

          break
        end
        @z.run(str, SYNC_FLUSH, nil) unless str.empty?
        break if @z.buf_filled > 0
      end
      @z.buf_filled
    end

    def calc_crc(str)
      if str.bytesize <= @ungetc
        @ungetc -= str.bytesize
      else
        @crc = Zlib.send(:checksum_of, CRC, @crc, @ungetc.zero? ? str : str.byteslice(@ungetc, str.bytesize - @ungetc))
        @ungetc = 0
      end
    end

    # gzfile_newstr: decoded bytes in the file's encoding, converted from
    # the external one where two were given.
    def newstr(str)
      return str.force_encoding(@enc) if @enc2.nil?

      begin
        str.dup.force_encoding(@enc2).encode(@enc, **(@ecopts || {}))
      rescue EncodingError
        str
      end
    end

    def fill(len, outbuf)
      raise ArgumentError, "negative length #{len} given" if len < 0
      return 0 if len.zero?

      read_more(outbuf) while !@z.finished? && @z.buf_filled < len
      if finished?
        check_footer(outbuf) unless flag?(FLAG_FOOTER_FINISHED)
        return -1
      end
      [len, @z.buf_filled].min
    end

    def read(len, outbuf)
      len = fill(len, outbuf)
      if len <= 0
        outbuf&.clear
        return nil if len.negative?

        return outbuf || "".b
      end

      dst = @z.shift_buffer(len, outbuf)
      calc_crc(dst) unless dst.nil?
      dst
    end

    def readpartial(len, outbuf)
      raise ArgumentError, "negative length #{len} given" if len < 0
      if len.zero?
        return "".b if outbuf.nil?

        return outbuf.clear
      end

      read_more(outbuf) while !@z.finished? && @z.buf_filled.zero?
      if finished?
        check_footer(outbuf) unless flag?(FLAG_FOOTER_FINISHED)
        outbuf&.clear
        raise EOFError, "end of file reached"
      end

      dst = @z.shift_buffer(len, outbuf)
      calc_crc(dst)
      dst
    end

    def read_all(dst)
      read_more(dst) until @z.finished?
      if finished?
        check_footer(dst) unless flag?(FLAG_FOOTER_FINISHED)
        return dst.nil? ? "".b : dst.clear
      end

      dst = @z.detach_buffer(nil)
      return dst if dst.nil?

      calc_crc(dst)
      newstr(dst)
    end

    def getc
      len = mbmaxlen
      read_more(nil) while !@z.finished? && @z.buf_filled < len
      if finished?
        check_footer(nil) unless flag?(FLAG_FOOTER_FINISHED)
        return nil
      end

      found, size = char_at(@z.buf, 0)
      dst = read(found == :found ? size : 1, nil)
      dst.nil? ? nil : newstr(dst)
    end

    def ungets(bytes)
      @z.buffer_ungets(bytes)
      @ungetc += bytes.bytesize
    end

    def rewind
      n = @z.total_in
      n += @z.input.bytesize unless @z.input.nil?
      @io.seek(-n, IO::SEEK_CUR)
      reset
    end

    def unused
      return nil unless @z.ready?
      return nil unless finished?

      check_footer(nil) unless flag?(FLAG_FOOTER_FINISHED)
      @z.input.nil? ? nil : String.new(@z.input)
    end

    # rb_gzfile_ecopts: the encodings the options name, the external one
    # converted to the internal one where they differ.
    def encodings(opts)
      return if opts.nil?

      external = opts[:external_encoding]
      internal = opts[:internal_encoding]
      if external.nil? && internal.nil? && (spec = opts[:encoding])
        external, internal = spec.to_s.split(":", 2)
      end
      return if external.nil? && internal.nil?

      external = external.nil? ? Encoding.default_external : Encoding.find(external.to_s.delete_prefix("BOM|"))
      internal = internal.nil? || internal.to_s == "-" ? nil : Encoding.find(internal)
      internal = Encoding.default_internal if internal.nil? && external != Encoding::BINARY
      if internal.nil? || internal == external
        @enc = external
        @enc2 = nil
      else
        @enc = internal
        @enc2 = external
        @ecopts = opts.except(:external_encoding, :internal_encoding, :encoding)
      end
    end

    def mbmaxlen = MBMAXLEN.fetch(@enc.name, 1)

    # rb_enc_left_char_head and rb_enc_precise_mbclen at `at` in `bytes`:
    # where the character holding that byte starts, and whether it is
    # whole there (:found, its length), cut short by the end
    # (:needmore, the bytes it lacks) or no character at all.
    def char_head(bytes, at)
      return at unless @enc == Encoding::UTF_8

      at -= 1 while at > 0 && (bytes.getbyte(at) & 0xc0) == 0x80
      at
    end

    def char_at(bytes, at)
      lead = bytes.getbyte(at)
      return [:found, 1] if lead < 0x80 || mbmaxlen == 1
      unless @enc == Encoding::UTF_8
        char = bytes.byteslice(at, mbmaxlen).force_encoding(@enc)[0]
        return [char.valid_encoding? ? :found : :invalid, char.bytesize]
      end

      need = if lead.between?(0xc2, 0xdf) then 2
             elsif lead.between?(0xe0, 0xef) then 3
             elsif lead.between?(0xf0, 0xf4) then 4
             end
      return [:invalid, 1] if need.nil?

      (1...need).each do |i|
        byte = bytes.getbyte(at + i)
        return [:needmore, need - i] if byte.nil?

        low, high = if i == 1 && lead == 0xe0 then [0xa0, 0xbf]
                    elsif i == 1 && lead == 0xed then [0x80, 0x9f]
                    elsif i == 1 && lead == 0xf0 then [0x90, 0xbf]
                    elsif i == 1 && lead == 0xf4 then [0x80, 0x8f]
                    else [0x80, 0xbf]
                    end
        return [:invalid, 1] unless byte.between?(low, high)
      end
      [:found, need]
    end

    # gzreader_charboundary: a limit that falls inside a character moved
    # to its end.
    def charboundary(n)
      head = char_head(@z.buf, n - 1)
      if head < n
        found, size = char_at(@z.buf, head)
        if found == :needmore
          got = fill(n + size, nil)
          return got if got > 0
        elsif found == :found
          return head + size
        end
      end
      n
    end

    def skip_linebreaks
      while @z.buf_filled.zero?
        return if finished?

        read_more(nil)
      end
      n = 0
      while @z.buf.getbyte(n) == 0x0a
        n += 1
        next unless n >= @z.buf_filled

        calc_crc(@z.detach_buffer(nil))
        while @z.buf_filled.zero?
          return if finished?

          read_more(nil)
        end
        n = 0
      end
      calc_crc(@z.shift_buffer(n, nil))
    end

    # gzreader_gets.
    def gets(args)
      limit = -1
      if args.empty?
        rs = $/
      else
        raise ArgumentError, "wrong number of arguments (given #{args.size}, expected 0..2)" if args.size > 2

        rs, lim = args
        if !lim.nil?
          rs = Primitive.zr_str_operand(rs) unless rs.nil?
        elsif !rs.nil?
          tmp = String.try_convert(rs)
          if tmp.nil?
            lim = rs
            rs = $/
          else
            rs = tmp
          end
        end
        unless lim.nil?
          limit = Primitive.zr_index_operand_m(lim)
          return "".b if limit.zero?
        end
      end

      if rs.nil?
        if limit < 0
          dst = read_all(nil)
          return nil if dst.empty?
        else
          n = fill(limit, nil)
          return nil if n <= 0

          n = mbmaxlen > 1 && n >= limit && !finished? ? charboundary(n) : limit
          dst = @z.shift_buffer(n, nil)
          return nil if dst.nil?

          calc_crc(dst)
          dst = newstr(dst)
        end
        @lineno += 1
        return dst
      end

      paragraph = rs.empty?
      sep = paragraph ? "\n\n".b : rs.b
      rslen = sep.bytesize
      skip_linebreaks if paragraph

      while @z.buf_filled < rslen
        if @z.finished?
          @lineno += 1 if @z.buf_filled > 0
          return read(rslen, nil)
        end
        read_more(nil)
      end

      first = sep.byteslice(0, 1)
      p = 0
      n = rslen
      while true
        if n > @z.buf_filled
          break if @z.finished?

          read_more(nil)
          p = n - rslen
        end
        filled = @z.buf_filled
        filled = limit if limit > 0 && filled >= limit
        at = @z.buf.byteindex(first, p)
        at = nil if at && at >= p + filled - n + 1
        if at.nil?
          n = filled
          break if limit > 0 && filled >= limit

          n += 1
        else
          n += at - p
          p = at
          break if rslen == 1 || @z.buf.byteslice(p, rslen) == sep

          p += 1
          n += 1
        end
      end
      n = charboundary(n) if mbmaxlen > 1 && n == limit && (@z.buf_filled > n || !@z.finished?)

      @lineno += 1
      dst = read(n, nil)
      return nil if dst.nil?

      skip_linebreaks if paragraph
      newstr(dst)
    end

    private

    def read_zero_terminated(outbuf)
      raise GzipFile::Error, "unexpected end of file" unless read_raw_ensure(1, outbuf)

      at = read_raw_until_zero(0)
      str = @z.input.byteslice(0, at)
      @z.discard_input(at + 1)
      str
    end

    def string_of(str)
      raise TypeError, "wrong argument type #{conversion_name(str)} (expected String)" unless str.is_a?(String)

      str
    end

    def writer_end
      return if @z.closing?

      flag(Stream::CLOSING)
      begin
        make_header unless flag?(FLAG_HEADER_FINISHED)
        @z.run("", FINISH, nil)
        make_footer
        write_raw
      ensure
        @z.end_stream
      end
    end

    def reader_end
      return if @z.closing?

      flag(Stream::CLOSING)
      begin
        check_footer(nil) if finished? && !flag?(FLAG_FOOTER_FINISHED)
      ensure
        @z.end_stream
      end
    end
  end
  private_constant :GzFile

  class GzipFile

    Primitive.zr_undef_allocator(self)

    class << self
      def wrap(*args, **opts, &block)
        wrapped(args, opts, false, &block)
      end

      private

      # gzfile_s_open: the file at the path, opened in `mode`, as the io.
      def opened(args, opts, mode, &block)
        Primitive.attr! :hidden
        raise ArgumentError, "wrong number of arguments (given 0, expected 1+)" if args.empty?

        args = [::File.open(args[0], mode), *args.drop(1)]
        wrapped(args, opts, true, &block)
      end

      # gzfile_wrap: a new file over the io, closed when the block is done.
      def wrapped(args, opts, close_io_on_error, &block)
        Primitive.attr! :hidden
        begin
          gz = new(*args, **opts)
        rescue Exception
          args[0].close if close_io_on_error
          raise
        end
        return gz unless block

        begin
          yield gz
        ensure
          gz.send(:ensure_closed)
        end
      end
    end

    def to_io = ready_gzfile.io

    def crc = ready_gzfile.crc

    def mtime = Time.at(ready_gzfile.mtime)

    def level = ready_gzfile.level

    def os_code = ready_gzfile.os_code

    def orig_name = ready_gzfile.orig_name&.dup

    def comment = ready_gzfile.comment&.dup

    def close
      gz = gzfile
      return nil unless gz.z.ready?

      io = gz.io
      gz.close(true)
      io
    end

    def finish
      gz = ready_gzfile
      io = gz.io
      gz.close(false)
      io
    end

    def closed? = gzfile.io.nil?

    def sync = ready_gzfile.flag?(GzFile::FLAG_SYNC)

    def sync=(mode)
      gz = ready_gzfile
      if mode
        gz.flag(GzFile::FLAG_SYNC)
      else
        gz.z.flags &= ~GzFile::FLAG_SYNC
      end
    end

    private

    def initialize_copy(orig)
      Primitive.attr! :hidden
      Primitive.zr_state_set(self, :__gzfile__, nil)
      Kernel.instance_method(:initialize_copy).bind_call(self, orig)
    end

    def gzfile
      Primitive.attr! :hidden
      Primitive.zr_hidden_get(self, :__gzfile__) ||
        Primitive.zr_state_set(self, :__gzfile__, GzFile.new(file_ending, holder: self))
    end

    # get_gzfile: the file, while it is open.
    def ready_gzfile
      Primitive.attr! :hidden
      gz = gzfile
      raise Error, "closed gzip stream" unless gz.z.ready?

      gz
    end

    def ensure_closed
      Primitive.attr! :hidden
      gz = gzfile
      gz.close(true) if gz.z.ready?
    end

    # The io's path, which this file answers as its own once it has one.
    def take_path(gz)
      Primitive.attr! :hidden
      return unless gz.io.respond_to?(:path)

      begin
        gz.path = gz.io.path
        define_singleton_method(:path) { Primitive.zr_hidden_get(self, :__gzfile__).path }
      rescue IOError
        nil
      end
    end
  end

  class GzipWriter < GzipFile
    Primitive.zr_define_alloc(self)

    def self.open(*args, **opts, &block)
      opened(args, opts, "wb", &block)
    end

    def initialize(*args)
      opt = args.size > 1 ? Hash.try_convert(args.last) : nil
      args.pop if opt
      raise ArgumentError, "wrong number of arguments (given #{args.size}, expected 1..3)" unless args.size.between?(1, 3)

      io, level, strategy = args
      gz = gzfile
      gz.level = Zlib.send(:level_arg, level)
      err = gz.z.init(gz.level, -MAX_WBITS, DEF_MEM_LEVEL, Zlib.send(:strategy_arg, strategy))
      Zlib.send(:raise_error, err, gz.z.message) unless err == Z_OK

      gz.io = io
      gz.z.ready
      gz.encodings(opt)
      take_path(gz)
      self
    end

    def mtime=(mtime)
      gz = ready_gzfile
      raise GzipFile::Error, "header is already written" if gz.flag?(GzFile::FLAG_HEADER_FINISHED)

      gz.mtime = Integer(mtime) & 0xffff_ffff
      gz.flag(GzFile::FLAG_MTIME_IS_SET)
      mtime
    end

    def orig_name=(str)
      ready_gzfile.orig_name = header_string(str)
      str
    end

    def comment=(str)
      ready_gzfile.comment = header_string(str)
      str
    end

    def pos = ready_gzfile.z.total_in

    def tell = ready_gzfile.z.total_in

    def flush(flush = nil)
      gz = ready_gzfile
      flush = Zlib.send(:flush_arg, flush, SYNC_FLUSH)
      gz.z.run("", flush, nil) unless flush == NO_FLUSH
      gz.write_raw
      gz.io.flush if gz.io.respond_to?(:flush)
      self
    end

    def write(*strs)
      gz = ready_gzfile
      strs.sum do |str|
        str = Primitive.zr_obj_as_string(str) unless str.is_a?(String)
        str = begin
          str.encode(gz.enc2)
        rescue EncodingError
          str
        end if gz.enc2 && gz.enc2 != Encoding::BINARY
        gz.write(str)
        str.bytesize
      end
    end

    def putc(ch)
      c = ch.is_a?(String) ? ch.getbyte(0) || 0 : Primitive.zr_index_operand_m(ch) & 0xff
      ready_gzfile.write(c.chr)
      ch
    end

    def <<(str)
      write(str)
      self
    end

    def printf(*args)
      write(format(*args))
      nil
    end

    def print(*objects) = IO.send(:print_to, self, objects)

    def puts(*objects)
      IO.send(:each_line_of, objects) { |*parts| write(*parts) }
      nil
    end

    private

    def file_ending
      Primitive.attr! :hidden
      :writer
    end

    def header_string(str)
      Primitive.attr! :hidden
      gz = ready_gzfile
      raise GzipFile::Error, "header is already written" if gz.flag?(GzFile::FLAG_HEADER_FINISHED)

      s = String.new(Primitive.zr_str_operand(str))
      at = s.byteindex("\0")
      at ? s.byteslice(0, at) : s
    end
  end

  class GzipReader < GzipFile
    include Enumerable

    Primitive.zr_define_alloc(self)

    class << self
      def open(*args, **opts, &block)
        opened(args, opts, "rb", &block)
      end

      def zcat(*args, &block)
        raise ArgumentError, "wrong number of arguments (given #{args.size}, expected 1..2)" unless args.size.between?(1, 2)

        io = args[0]
        buf = nil
        while true
          reader = new(*args)
          gz = reader.send(:ready_gzfile)
          if block
            while (line = gz.gets([]))
              yield line
            end
          else
            buf ||= "".b
            Zlib.send(:cat, buf, gz.read_all(nil))
          end

          gz.read_all(nil)
          pos = io.pos
          unused = gz.unused
          reader.finish
          unless unused.nil?
            pos -= unused.length
            io.pos = pos
          end
          break unless pos < io.size
        end
        block ? nil : buf
      end
    end

    def initialize(io, **opt)
      gz = gzfile
      err = gz.z.init(0, -MAX_WBITS, 0, 0)
      Zlib.send(:raise_error, err, gz.z.message) unless err == Z_OK

      gz.io = io
      gz.z.ready
      gz.read_header(nil)
      gz.encodings(opt.empty? ? nil : opt)
      take_path(gz)
      self
    end

    def lineno = ready_gzfile.lineno

    def lineno=(lineno)
      ready_gzfile.lineno = Zlib.send(:int, lineno)
    end

    def eof
      gz = ready_gzfile
      gz.read_more(nil) while !gz.z.finished? && gz.z.buf_filled.zero?
      gz.finished?
    end

    def eof? = eof

    def pos
      gz = ready_gzfile
      gz.z.total_out - gz.z.buf_filled
    end

    def tell = pos

    def rewind
      ready_gzfile.rewind
      0
    end

    def unused = gzfile.unused

    def read(len = nil, outbuf = nil)
      gz = ready_gzfile
      return gz.read_all(outbuf) if len.nil?

      len = Zlib.send(:int, len)
      raise ArgumentError, "negative length #{len} given" if len < 0

      gz.read(len, outbuf)
    end

    def readpartial(len, outbuf = nil)
      gz = ready_gzfile
      len = Zlib.send(:int, len)
      raise ArgumentError, "negative length #{len} given" if len < 0
      unless outbuf.nil? || outbuf.is_a?(String)
        raise TypeError, "wrong argument type #{conversion_name(outbuf)} (expected String)"
      end

      gz.readpartial(len, outbuf)
    end

    def getc = ready_gzfile.getc

    def readchar = getc || raise(EOFError, "end of file reached")

    def getbyte = ready_gzfile.read(1, nil)&.getbyte(0)

    def readbyte = getbyte || raise(EOFError, "end of file reached")

    def each_char
      return enum_for(:each_char) unless block_given?

      while (c = getc)
        yield c
      end
      nil
    end

    def each_byte
      return enum_for(:each_byte) unless block_given?

      while (b = getbyte)
        yield b
      end
      nil
    end

    def ungetc(s)
      return ungetbyte(s) if s.is_a?(Integer)

      gz = ready_gzfile
      s = Primitive.zr_str_operand(s)
      s = s.encode(gz.enc2) if gz.enc2 && gz.enc2 != Encoding::BINARY
      gz.ungets(s)
      nil
    end

    def ungetbyte(ch)
      gz = ready_gzfile
      c = ch.is_a?(String) ? ch.getbyte(0) || 0 : Primitive.zr_index_operand_m(ch) & 0xff
      gz.ungets(c.chr)
      nil
    end

    def gets(*args)
      line = ready_gzfile.gets(args)
      $_ = line unless line.nil?
      line
    end

    def readline(*args) = gets(*args) || raise(EOFError, "end of file reached")

    def each(*args)
      return enum_for(:each) unless block_given?

      gz = ready_gzfile
      while (line = gz.gets(args))
        yield line
      end
      self
    end

    def each_line(*args)
      return enum_for(:each_line) unless block_given?

      gz = ready_gzfile
      while (line = gz.gets(args))
        yield line
      end
      self
    end

    def readlines(*args)
      gz = ready_gzfile
      lines = []
      while (line = gz.gets(args))
        lines << line
      end
      lines
    end

    def external_encoding = ready_gzfile.enc

    private

    def file_ending
      Primitive.attr! :hidden
      :reader
    end
  end
end
