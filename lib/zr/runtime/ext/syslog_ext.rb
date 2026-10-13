# frozen_string_literal: true

# syslog.c, in ruby: one process-wide connection to the system logger,
# which the gem's own syslog.rb requires as syslog_ext.
module Syslog
  module Constants; end
  module Option; end
  module Facility; end
  module Level; end
  module Macros; end

  VERSION = "0.4.0"

  # <syslog.h>'s values on this host.
  { LOG_PID: 0x01, LOG_CONS: 0x02, LOG_ODELAY: 0x04, LOG_NDELAY: 0x08, LOG_NOWAIT: 0x10, LOG_PERROR: 0x20 }
    .each { |name, value| Option.const_set(name, value) }
  { LOG_AUTH: 4 << 3, LOG_AUTHPRIV: 10 << 3, LOG_CRON: 9 << 3, LOG_DAEMON: 3 << 3, LOG_FTP: 11 << 3, LOG_KERN: 0 << 3,
    LOG_LPR: 6 << 3, LOG_MAIL: 2 << 3, LOG_NEWS: 7 << 3, LOG_SYSLOG: 5 << 3, LOG_USER: 1 << 3, LOG_UUCP: 8 << 3,
    LOG_LOCAL0: 16 << 3, LOG_LOCAL1: 17 << 3, LOG_LOCAL2: 18 << 3, LOG_LOCAL3: 19 << 3, LOG_LOCAL4: 20 << 3,
    LOG_LOCAL5: 21 << 3, LOG_LOCAL6: 22 << 3, LOG_LOCAL7: 23 << 3 }
    .each { |name, value| Facility.const_set(name, value) }
  LEVELS = { LOG_EMERG: 0, LOG_ALERT: 1, LOG_CRIT: 2, LOG_ERR: 3, LOG_WARNING: 4, LOG_NOTICE: 5, LOG_INFO: 6, LOG_DEBUG: 7 }.freeze
  LEVELS.each { |name, value| Level.const_set(name, value) }
  private_constant :LEVELS

  # The connection's state is the module's, whatever object a module
  # function runs on, as syslog.c keeps it in statics.
  class << self
    private

    attr_reader :ident_text, :option_bits, :facility_code, :mask_bits

    def connect(ident, options, facility)
      Primitive.attr! :hidden
      raise RuntimeError, "syslog already open" if @opened

      ident = Primitive.zr_str_operand(ident.nil? ? $0 : ident)
      raise ArgumentError, "string contains null byte" if ident.include?("\0")

      @ident_text = ident.dup
      @option_bits = options.nil? ? Option::LOG_PID | Option::LOG_CONS : Integer(options)
      @facility_code = facility.nil? ? Facility::LOG_USER : Integer(facility)
      mask = Primitive.zr_syslog_open(@ident_text, @option_bits, @facility_code)
      @opened = true
      @mask_bits = Primitive.zr_syslog_mask(mask)
    end

    def disconnect
      Primitive.attr! :hidden
      raise RuntimeError, "syslog not opened" unless @opened

      Primitive.zr_syslog_close
      @ident_text = @option_bits = @facility_code = @mask_bits = nil
      @opened = false
      nil
    end

    def connected? = @opened ? true : false

    def set_mask(mask)
      Primitive.attr! :hidden
      raise RuntimeError, "must open syslog before setting log mask" unless @opened

      # NUM2INT: a Float is cut to an Integer, a String is refused.
      @mask_bits = Integer.send(:int_operand, mask)
      Primitive.zr_syslog_mask(@mask_bits)
    end

    # syslog_write: the arguments as sprintf formats them, as one message.
    def write(priority, args)
      Primitive.attr! :hidden
      raise ArgumentError, "no log message supplied" if args.empty?
      raise RuntimeError, "must open syslog before write" unless @opened

      Primitive.zr_syslog_write(priority, format(*args).gsub("%", "%%"))
    end
  end

  def open(ident = nil, options = nil, facility = nil)
    Syslog.send(:connect, ident, options, facility)
    return Syslog unless block_given?

    begin
      yield Syslog
    ensure
      Syslog.close
    end
    Syslog
  end

  def reopen(*args, &block)
    Syslog.close
    Syslog.open(*args, &block)
  end

  def open!(*args, &block)
    Syslog.close
    Syslog.open(*args, &block)
  end

  def opened? = Syslog.send(:connected?)

  def ident = opened? ? Syslog.send(:ident_text).dup : nil

  def options = opened? ? Syslog.send(:option_bits) : nil

  def facility = opened? ? Syslog.send(:facility_code) : nil

  def log(priority, *args)
    raise TypeError, "type mismatch: #{priority.class} given" unless priority.is_a?(Integer)

    Syslog.send(:write, priority, args)
    Syslog
  end

  def close = Syslog.send(:disconnect)

  def mask = opened? ? Syslog.send(:mask_bits) : nil

  def mask=(mask)
    Syslog.send(:set_mask, mask)
    mask
  end

  def instance = Syslog

  LEVELS.each_key do |name|
    define_method(name.to_s.delete_prefix("LOG_").downcase) do |*args|
      Syslog.send(:write, LEVELS.fetch(name), args)
      Syslog
    end
  end

  module_function :open, :reopen, :open!, :opened?, :ident, :options, :facility, :log, :close, :mask, :mask=, :instance,
                  *LEVELS.keys.map { |name| name.to_s.delete_prefix("LOG_").downcase.to_sym }
  # reopen and open! are one C function, so their Methods are equal.
  [self, singleton_class].each { |owner| Primitive.zr_method_alias_of(owner, :reopen, :open!) }

  def self.inspect
    return "<##{self}: opened=false>" unless opened?

    "<##{self}: opened=true, ident=\"#{ident}\", options=#{options}, facility=#{facility}, mask=#{mask}>"
  end

  module Macros
    def LOG_MASK(pri) = 1 << Integer(pri)

    def LOG_UPTO(pri) = (1 << (Integer(pri) + 1)) - 1

    def self.included(target)
      target.extend(Macros)
      self
    end
  end

  module Constants
    include Option
    include Facility
    include Level
    include Macros

    def self.included(target)
      target.extend(Macros)
      self
    end
  end

  include Constants
end
