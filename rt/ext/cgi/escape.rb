# frozen_string_literal: true

# The escapes CGI ships as a C extension, in ruby. Only these six pairs
# live in `cgi/escape`; the rest of CGI is its own library.
module CGI
  module Escape
    HTML = { "'" => "&#39;", "&" => "&amp;", '"' => "&quot;", "<" => "&lt;", ">" => "&gt;" }.freeze
    UNHTML = { "amp" => "&", "quot" => '"', "gt" => ">", "lt" => "<", "apos" => "'", "nbsp" => " " }.freeze
    # Everything a URI component may hold unescaped, and the same set
    # plus the space that `escape` writes as a plus.
    SAFE = /[^a-zA-Z0-9_\-.~]/
    FORM_SAFE = /[^a-zA-Z0-9_\-.* ]/

    def escapeHTML(string)
      string.gsub(/['&"<>]/, HTML)
    end

    def unescapeHTML(string)
      return string unless string.include?("&")

      string.gsub(/&(?:([A-Za-z]+)|#([0-9]+)|#[xX]([0-9A-Fa-f]+));/) do
        name, decimal, hex = $1, $2, $3
        if name then UNHTML.fetch(name.downcase) { $& }
        else (decimal ? decimal.to_i : hex.to_i(16)).chr(string.encoding)
        end
      end
    end

    # The form encoding: a space is a plus, and `*`, `-`, `.` and `_`
    # stand as they are.
    def escape(string)
      string.to_s.b.gsub(FORM_SAFE) { |c| format("%%%02X", c.ord) }.tr(" ", "+").force_encoding(string.encoding)
    end

    def unescape(string, encoding = Encoding::UTF_8)
      string.to_s.b.tr("+", " ").gsub(/%(\h\h)/) { $1.to_i(16).chr }.force_encoding(encoding)
    end

    def escapeURIComponent(string)
      string.to_s.b.gsub(SAFE) { |c| format("%%%02X", c.ord) }.force_encoding(string.encoding)
    end

    def unescapeURIComponent(string, encoding = Encoding::UTF_8)
      string.to_s.b.gsub(/%(\h\h)/) { $1.to_i(16).chr }.force_encoding(encoding)
    end

    def escapeElement(string, *elements)
      elements = elements.flatten
      string.gsub(%r{<\/?(?:#{elements.join("|")})(?!\w)(?:.|\n)*?>}i) { escapeHTML($&) }
    end

    def unescapeElement(string, *elements)
      elements = elements.flatten
      string.gsub(%r{&lt;\/?(?:#{elements.join("|")})(?!\w)(?:.|\n)*?&gt;}i) { unescapeHTML($&) }
    end

    alias escape_html escapeHTML
    alias unescape_html unescapeHTML
    alias escape_element escapeElement
    alias unescape_element unescapeElement
    alias escape_uri_component escapeURIComponent
    alias unescape_uri_component unescapeURIComponent
    alias h escapeHTML
  end

  extend Escape
end
