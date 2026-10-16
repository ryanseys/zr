# frozen_string_literal: true

# Symbol's methods. Most read the name as a String and call String's own
# methods on it, as CRuby's sym_* functions call rb_str_*.
class Symbol
  include Comparable

  # Ruby keeps one frozen name String per symbol (rb_sym2str), so `to_s`,
  # `name` and `id2name` return the same object each time.
  NAMES = Hash.new { |cache, symbol| cache[symbol] = Primitive.zr_sym_name_m(symbol) }
  private_constant :NAMES

  # The name as the core reads it, as rb_sym2str gives it: a `to_s` that
  # the program writes changes interpolation, not Symbol's own methods.
  def own_text
    Primitive.attr! :hidden
    NAMES[self]
  end

  # String's own methods on the name, as CRuby's sym_* functions call
  # rb_str_* in C: a prepend or a redefinition of a String method does
  # not change Symbol's, and from this hidden frame String's frame does
  # not show in a backtrace (zr_frame_shown_p).
  def text_aref(index, length, absent)
    Primitive.attr! :hidden
    absent ? own_text[index] : own_text[index, length]
  end

  def on_text(name, args)
    Primitive.attr! :hidden
    text = own_text
    case name
    when :upcase then text.upcase(*args)
    when :downcase then text.downcase(*args)
    when :capitalize then text.capitalize(*args)
    when :swapcase then text.swapcase(*args)
    when :succ then text.succ
    when :start_with? then text.start_with?(*args)
    when :end_with? then text.end_with?(*args)
    end
  end

  def [](index, length = (absent = true; nil)) = text_aref(index, length, absent)
  alias slice []

  def length = Primitive.zr_str_length_m(own_text)
  alias size length

  def =~(other) = own_text =~ other
  def match(*args, &block) = own_text.match(*args, &block)
  def match?(*args) = own_text.match?(*args)

  def upcase(*options) = Primitive.zr_str_sym_m(on_text(:upcase, options))
  def downcase(*options) = Primitive.zr_str_sym_m(on_text(:downcase, options))
  def capitalize(*options) = Primitive.zr_str_sym_m(on_text(:capitalize, options))
  def swapcase(*options) = Primitive.zr_str_sym_m(on_text(:swapcase, options))
  def succ = Primitive.zr_str_sym_m(on_text(:succ, nil))
  alias next succ

  def start_with?(*prefixes) = on_text(:start_with?, prefixes)
  def end_with?(*suffixes) = on_text(:end_with?, suffixes)
  def empty? = Primitive.zr_str_bytesize(own_text) == 0

  # A name that contains a character outside ASCII. If all its
  # characters have a category of their own, it shows as the runtime
  # writes it. If one needs an escape, the name is quoted and escaped.
  def utf8_inspect
    Primitive.attr! :hidden
    text = own_text
    shown = text.utf8_inspect
    plain = shown == "\"#{text}\""
    # sym_printable takes NEL as printable; String#inspect alone escapes
    # it. So a name that is plain but for NEL is bare.
    if plain || shown == "\"#{text.gsub("\u0085") { "\\u0085" }}\""
      bare = Primitive.zr_sym_inspect_bytes(self)
      return bare if plain || !bare.start_with?(":\"")
    end

    ":#{shown}"
  end

  # A name with a character outside ASCII in an encoding other than
  # UTF-8. It is bare only when its String prints as itself and the name
  # is plain with each such character taken as a letter
  # (rb_enc_symname_type).
  def mb_inspect
    Primitive.attr! :hidden
    text = own_text
    shown = text.inspect
    if shown.byteslice(1, shown.bytesize - 2) == text
      letters = text.each_char.map { |char| char.ascii_only? ? char : "a" }.join
      return ":#{text}" unless Primitive.zr_sym_inspect_bytes(letters.to_sym).start_with?(":\"")
    end
    ":#{shown}"
  end

  # The last characters that make Hash#inspect quote a key, as
  # symbol_key_needs_quote lists them.
  KEY_QUOTED_ENDS = %w[+ - * / ` % ^ & | \] < = > ~ @].freeze
  private_constant :KEY_QUOTED_ENDS

  # This symbol as Hash#inspect writes a key with a name outside ASCII:
  # bare when the name is plain, else quoted as its String inspects.
  def key_inspect
    Primitive.attr! :hidden
    shown = inspect
    text = own_text
    if shown.start_with?(":\"") || text.start_with?("@", "$", "!") || KEY_QUOTED_ENDS.include?(text[-1])
      text.inspect
    else
      shown.byteslice(1, shown.bytesize - 1)
    end
  end

  def to_sym = self

  def intern = self

  def casecmp(other) = other.is_a?(Symbol) ? own_text.casecmp(other.own_text) : nil

  def casecmp?(other) = other.is_a?(Symbol) ? own_text.casecmp?(other.own_text) : nil

  def to_s = NAMES[self]
  alias id2name to_s
  alias name to_s

  def self.all_symbols = Primitive.zr_all_symbols

  def encoding = own_text.encoding
end
