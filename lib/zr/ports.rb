# frozen_string_literal: true

require_relative "paths"

module Zr
  # The gems with a C part that zr implements in Ruby. zr owns each one, as
  # JRuby owns its json: the Ruby half that the gem ships (vendor/ext/<gem>/lib,
  # when it has one) and zr's port of the C half (runtime/ext) come
  # together, at one version. stdlib/ never holds them.
  #
  # Some versions are newer than the ones ruby 4.0.7 ships (json 3.0.2,
  # not 2.18.0): docs/reference/differences-from-ruby.md lists them.
  module Ports
    # One port: the gem's version, the versions whose C interface the port
    # implements (a rubygems requirement, read only when a build selects
    # another version of the gem), and whether vendor/ext has its Ruby
    # half.
    Port = Struct.new(:version, :compat, :ruby, keyword_init: true)

    def self.port(version, compat: "~> #{version}", ruby: true) = Port.new(version: version, compat: compat, ruby: ruby).freeze

    ALL = {
      # A Ruby half in vendor/ext, over a port in runtime/ext.
      "prism" => port("1.9.0"),
      "json" => port("3.0.2"),
      "psych" => port("5.3.1"),
      "bigdecimal" => port("4.1.2"),
      "digest" => port("3.2.1"),
      "syslog" => port("0.4.0"),
      "ffi" => port("1.17.4"),
      "openssl" => port("4.0.2"),
      "nkf" => port("0.3.0"),
      "fiddle" => port("1.1.8"),
      # All in runtime/ext: the C of ruby 4.0.7's default gem, in Ruby.
      "date" => port("3.5.1", ruby: false),
      "stringio" => port("3.2.0", ruby: false),
      "strscan" => port("3.1.6", ruby: false),
      "zlib" => port("3.2.3", ruby: false),
      "io-console" => port("0.8.2", ruby: false),
      "etc" => port("1.4.6", ruby: false),
      "fcntl" => port("1.3.0", ruby: false)
    }.freeze

    # The Ruby halves in vendor/ext, in the order a require searches them.
    # socket is part of ruby, not a gem, and comes with them.
    def self.roots = (ALL.select { |_, port| port.ruby }.keys + ["socket"]).map { |name| File.join(Paths::VENDOR, "ext/#{name}/lib") }
  end
end
