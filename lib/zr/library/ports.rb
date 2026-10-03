# frozen_string_literal: true

require_relative "layout"

module Zr
  module Library
    # The gems with a C part that zr implements in Ruby. zr owns each one, as
    # JRuby owns its json: the gem's Ruby half, as the gem ships it, and zr's
    # port of the C half (lib/zr/runtime/ext) come together, at one version.
    #
    # A port with `vendored: true` is vendored as a gem at zr's version
    # (vendor/ruby/lib/ruby/gems/4.0.0/gems/<name>-<version>, which
    # `zr-dev vendor` writes). It comes before ruby's own library on the
    # load path, as rubygems activates an installed gem over a default gem.
    # One with `vendored: false` has its Ruby half in ruby's own library at the
    # same version (psych, openssl), or has no Ruby half (zlib).
    #
    # Some versions are newer than the ones ruby 4.0.7 ships (json 3.0.2,
    # not 2.18.0): docs/reference/differences-from-ruby.md lists them.
    module Ports
      # One port: the gem's version, the versions whose C interface the port
      # implements (a rubygems requirement, read only when a build selects
      # another version of the gem), and whether vendor/ holds the gem.
      # @rbs skip -- typed in sig/zr/library/ports.rbs
      Port = Struct.new(:version, :compat, :vendored, keyword_init: true)

      #: (String version, ?compat: String, ?vendored: bool) -> Port
      def self.port(version, compat: "~> #{version}", vendored: true) = Port.new(version: version, compat: compat, vendored: vendored).freeze

      ALL = {
        # A gem in vendor/, over a port in lib/zr/runtime/ext.
        "prism" => port("1.9.0"),
        "json" => port("3.0.2"),
        "psych" => port("5.3.1", vendored: false),
        "bigdecimal" => port("4.1.2"),
        "digest" => port("3.2.1", vendored: false),
        "syslog" => port("0.4.0"),
        "ffi" => port("1.17.4"),
        "openssl" => port("4.0.2", vendored: false),
        "nkf" => port("0.3.0"),
        "fiddle" => port("1.1.8"),
        "racc" => port("1.8.1"),
        # The C of ruby 4.0.7's default gem, in lib/zr/runtime/ext. Its Ruby half,
        # if any, is ruby's own at the same version.
        "date" => port("3.5.1", vendored: false),
        "stringio" => port("3.2.0", vendored: false),
        "strscan" => port("3.1.6", vendored: false),
        "zlib" => port("3.2.3", vendored: false),
        "io-console" => port("0.8.2", vendored: false),
        "etc" => port("1.4.6", vendored: false),
        "fcntl" => port("1.3.0", vendored: false)
      }.freeze #: Hash[String, Port]

      # The lib directory of each gem that vendor/ holds, in the order a
      # require searches them.
      #: () -> Array[String]
      def self.roots = ALL.select { |_, port| port.vendored }.map { |name, port| lib(name, port.version) }

      # The lib directory of port `name` in vendor/.
      #: (String name, ?String version) -> String
      def self.lib(name, version = ALL.fetch(name).version) = File.join(Layout.gem_root(name, version), "lib")
    end
  end
end
