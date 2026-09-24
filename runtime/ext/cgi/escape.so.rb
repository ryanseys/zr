# frozen_string_literal: true

# The escapes cgi/escape.so writes in C, in ruby. The library's own ruby
# half (vendor/lib/cgi/escape.rb) requires this file where it requires
# the extension, so everything around it is the library as written. An
# escape reads the bytes of a string in an ASCII-compatible encoding and
# leaves any other string to that ruby half, as the extension calls
# `super` for one.
class CGI
  module EscapeExt
    HTML = { "'" => "&#39;", "&" => "&amp;", '"' => "&quot;", "<" => "&lt;", ">" => "&gt;" }.freeze
    UNHTML = { "apos" => "'", "amp" => "&", "quot" => '"', "gt" => ">", "lt" => "<" }.freeze
    # What a URL leaves as it is: RFC 3986's unreserved characters.
    RESERVED = /[^a-zA-Z0-9\-._~]/n
    private_constant :HTML, :UNHTML, :RESERVED

    def escapeHTML(str)
      str = Primitive.zr_str_operand(str)
      return super(str) unless str.encoding.ascii_compatible?

      escaped = str.b.gsub(/['&"<>]/n, HTML)
      escaped.bytesize > str.bytesize ? escaped.force_encoding(str.encoding) : str.dup
    end

    # optimized_unescape_html: the five names, and a character reference
    # below the encoding's limit, which a UTF-8 string takes as its
    # character's bytes and any other as one byte.
    def unescapeHTML(str)
      str = Primitive.zr_str_operand(str)
      return super(str) unless str.encoding.ascii_compatible?

      limit = case str.encoding.name.upcase
              when "UTF-8" then 0x110000
              when "ISO-8859-1" then 256
              else 128
              end
      changed = false
      out = str.b.gsub(/&(?:(apos|amp|quot|gt|lt);|#(\d+);|#[xX](\h+);)/n) do
        name, decimal, hex = $1, $2, $3
        code = decimal ? decimal.to_i : hex&.hex
        if name
          changed = true
          UNHTML.fetch(name)
        elsif code < limit
          changed = true
          limit > 256 ? [code].pack("U").b : code.chr.b
        else
          $&
        end
      end
      changed ? out.force_encoding(str.encoding) : str.dup
    end

    def escape(str)
      str = Primitive.zr_str_operand(str)
      return super(str) unless str.encoding.ascii_compatible?

      escaped(str, plus: true)
    end

    def unescape(*args)
      raise ArgumentError, "wrong number of arguments (given #{args.size}, expected 1..2)" unless args.size.between?(1, 2)

      str = Primitive.zr_str_operand(args[0])
      return super unless str.encoding.ascii_compatible?

      unescaped(str, args.size > 1 ? args[1] : accept_charset, plus: true)
    end

    def escapeURIComponent(str)
      str = Primitive.zr_str_operand(str)
      return super(str) unless str.encoding.ascii_compatible?

      escaped(str, plus: false)
    end
    alias escape_uri_component escapeURIComponent

    def unescapeURIComponent(*args)
      raise ArgumentError, "wrong number of arguments (given #{args.size}, expected 1..2)" unless args.size.between?(1, 2)

      str = Primitive.zr_str_operand(args[0])
      return super unless str.encoding.ascii_compatible?

      unescaped(str, args.size > 1 ? args[1] : accept_charset, plus: false)
    end
    alias unescape_uri_component unescapeURIComponent

    private

    # optimized_escape: each reserved byte as `%XX`, and a space as `+`
    # when the form encoding requests one.
    def escaped(str, plus:)
      Primitive.attr! :hidden
      bytes = str.b
      return str.dup unless bytes.match?(RESERVED)

      bytes.gsub(RESERVED) { |c| plus && c == " " ? "+" : format("%%%02X", c.ord) }.force_encoding(str.encoding)
    end

    # optimized_unescape: each `%XX` as its byte, and a `+` as a space
    # where the form encoding wrote one. A `%` with no room for two hex
    # digits after it ends the scan. The bytes take `encoding` when they
    # are valid in it, and keep the string's own when they are not.
    def unescaped(str, encoding, plus:)
      Primitive.attr! :hidden
      encoding = Encoding.find(encoding) unless encoding.is_a?(Encoding)
      bytes = str.b
      out = nil
      from = 0
      i = 0
      while i < bytes.bytesize
        byte = bytes.getbyte(i)
        if byte == 0x25
          break if i + 3 > bytes.bytesize

          hex = bytes.byteslice(i + 1, 2)
          unless hex.match?(/\A\h\h\z/n)
            i += 1
            next
          end
          (out ||= "".b) << bytes.byteslice(from, i - from) << hex.hex.chr
          from = i += 3
        elsif plus && byte == 0x2B
          (out ||= "".b) << bytes.byteslice(from, i - from) << " "
          from = i += 1
        else
          i += 1
        end
      end
      out = out ? out << bytes.byteslice(from, bytes.bytesize - from) : str.dup
      out.force_encoding(encoding)
      out.valid_encoding? ? out : out.force_encoding(str.encoding)
    end

    # The charset CGI::Escape keeps, read as CLASS_OF(self) reads it.
    def accept_charset
      Primitive.attr! :hidden
      singleton_class.class_variable_get(:@@accept_charset)
    end
  end

  module Escape
    prepend EscapeExt
  end

  extend EscapeExt
end
