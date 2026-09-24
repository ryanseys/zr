# frozen_string_literal: true
# shareable_constant_value: literal

require_relative "ruby"

# Init_prism (extension.c) and Init_prism_pack (api_pack.c): the Prism
# constant and singleton methods prism's C extension defines, answered by
# the Ruby port. A gem's own Ruby half then finds Prism as it would after
# the C extension loads.
module Prism
  VERSION = Ruby::Dump::VERSION.join(".").b.freeze

  class << self
    def lex(...) = Ruby.lex(...)
    def lex_file(...) = Ruby.lex_file(...)
    def parse(...) = Ruby.parse(...)
    def parse_file(...) = Ruby.parse_file(...)
    def profile(...) = Ruby.profile(...)
    def profile_file(...) = Ruby.profile_file(...)
    def parse_stream(...) = Ruby.parse_stream(...)
    def parse_comments(...) = Ruby.parse_comments(...)
    def parse_file_comments(...) = Ruby.parse_file_comments(...)
    def parse_lex(...) = Ruby.parse_lex(...)
    def parse_lex_file(...) = Ruby.parse_lex_file(...)
    def parse_success?(...) = Ruby.parse_success?(...)
    def parse_failure?(...) = Ruby.parse_failure?(...)
    def parse_file_success?(...) = Ruby.parse_file_success?(...)
    def parse_file_failure?(...) = Ruby.parse_file_failure?(...)
    def dump(...) = Ruby.dump(...)
    def dump_file(...) = Ruby.dump_file(...)
  end

  class StringQuery
    def self.local?(string) = Ruby::StringQuery.local?(string)
    def self.constant?(string) = Ruby::StringQuery.constant?(string)
    def self.method_name?(string) = Ruby::StringQuery.method_name?(string)
  end

  module Pack
    class Directive; end
    class Format; end

    def self.parse(version, variant, source) = Ruby::Pack.parse(version, variant, source)
  end
end
