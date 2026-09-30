# frozen_string_literal: true

require_relative "paths"

module Zr
  # The gems with a C part that zr implements in Ruby. zr owns each one, as
  # JRuby owns its json: the gem's Ruby half, as the gem ships it, and zr's
  # port of the C half (runtime/ext) come together, at one version.
  #
  # A port with `gem: true` is vendored as a gem at zr's version
  # (vendor/ruby/lib/ruby/gems/4.0.0/gems/<name>-<version>, which
  # `zr-dev vendor` writes). It comes before ruby's own library on the
  # load path, as rubygems activates an installed gem over a default gem.
  # One with `gem: false` has its Ruby half in ruby's own library at the
  # same version (psych, openssl), or has no Ruby half (zlib).
  #
  # Some versions are newer than the ones ruby 4.0.7 ships (json 3.0.2,
  # not 2.18.0): docs/reference/differences-from-ruby.md lists them.
  module Ports
    # One port: the gem's version, the versions whose C interface the port
    # implements (a rubygems requirement, read only when a build selects
    # another version of the gem), and whether vendor/ holds the gem.
    Port = Struct.new(:version, :compat, :gem, keyword_init: true)

    def self.port(version, compat: "~> #{version}", gem: true) = Port.new(version: version, compat: compat, gem: gem).freeze

    ALL = {
      # A gem in vendor/, over a port in runtime/ext.
      "prism" => port("1.9.0"),
      "json" => port("3.0.2"),
      "psych" => port("5.3.1", gem: false),
      "bigdecimal" => port("4.1.2"),
      "digest" => port("3.2.1", gem: false),
      "syslog" => port("0.4.0"),
      "ffi" => port("1.17.4"),
      "openssl" => port("4.0.2", gem: false),
      "nkf" => port("0.3.0"),
      "fiddle" => port("1.1.8"),
      "racc" => port("1.8.1"),
      # The C of ruby 4.0.7's default gem, in runtime/ext. Its Ruby half,
      # if any, is ruby's own at the same version.
      "date" => port("3.5.1", gem: false),
      "stringio" => port("3.2.0", gem: false),
      "strscan" => port("3.1.6", gem: false),
      "zlib" => port("3.2.3", gem: false),
      "io-console" => port("0.8.2", gem: false),
      "etc" => port("1.4.6", gem: false),
      "fcntl" => port("1.3.0", gem: false)
    }.freeze

    # The lib directory of each gem that vendor/ holds, in the order a
    # require searches them.
    def self.roots = ALL.select { |_, port| port.gem }.map { |name, port| lib(name, port.version) }

    # The lib directory of port `name` in vendor/.
    def self.lib(name, version = ALL.fetch(name).version) = File.join(Layout.gem_root(name, version), "lib")
  end
end
