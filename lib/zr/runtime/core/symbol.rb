# frozen_string_literal: true

# Symbol's methods. Most read the name as a String and call String's own
# methods on it, as CRuby's sym_* functions call rb_str_*.
class Symbol
  include Comparable

  # The String method entries as they are at boot. Ruby reaches its own
  # C functions from here, so a prepend or a redefinition of a String
  # method does not change Symbol's.
  STRING = %i[[] length upcase downcase capitalize swapcase succ start_with? end_with? empty? casecmp casecmp?]
             .to_h { |name| [name, String.instance_method(name)] }.freeze
  private_constant :STRING

  # The name as the core reads it, as rb_sym2str gives it: a `to_s` that
  # the program writes changes interpolation, not Symbol's own methods.
  TO_S = instance_method(:to_s)
  private_constant :TO_S

  def own_text
    Primitive.attr! :hidden
    TO_S.bind_call(self)
  end

  def [](*args) = STRING[:[]].bind_call(own_text, *args)
  alias slice []

  def length = STRING[:length].bind_call(own_text)
  alias size length

  def =~(other) = own_text =~ other
  def match(*args, &block) = own_text.match(*args, &block)
  def match?(*args) = own_text.match?(*args)

  def upcase(*options) = STRING[:upcase].bind_call(own_text, *options).to_sym
  def downcase(*options) = STRING[:downcase].bind_call(own_text, *options).to_sym
  def capitalize(*options) = STRING[:capitalize].bind_call(own_text, *options).to_sym
  def swapcase(*options) = STRING[:swapcase].bind_call(own_text, *options).to_sym
  def succ = STRING[:succ].bind_call(own_text).to_sym
  alias next succ

  def start_with?(*prefixes) = STRING[:start_with?].bind_call(own_text, *prefixes)
  def end_with?(*suffixes) = STRING[:end_with?].bind_call(own_text, *suffixes)
  def empty? = STRING[:empty?].bind_call(own_text)

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

  def casecmp(other) = other.is_a?(Symbol) ? STRING[:casecmp].bind_call(own_text, other.own_text) : nil

  def casecmp?(other) = other.is_a?(Symbol) ? STRING[:casecmp?].bind_call(own_text, other.own_text) : nil
  # Ruby keeps one frozen name String per symbol (rb_sym2str), so `to_s`,
  # `name` and `id2name` return the same object each time.
  NAMES = Hash.new { |cache, symbol| cache[symbol] = Primitive.zr_sym_name_m(symbol) }
  private_constant :NAMES

  def to_s = NAMES[self]
  alias id2name to_s
  alias name to_s

  def self.all_symbols = Primitive.zr_all_symbols

  def encoding = own_text.encoding
end
