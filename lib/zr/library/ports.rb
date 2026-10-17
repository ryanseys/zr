# frozen_string_literal: true

require_relative "layout"

module Zr
  module Library
    # The gems with a C part that zr implements in Ruby. zr owns each one, as
    # JRuby owns its json: the gem's Ruby half, as the gem ships it, and zr's
    # port of the C half (lib/zr/runtime/ext) come together, at one version.
    #
    # A port with `vendored: true` is vendored as a gem at zr's version
    # (vendor/ruby/lib/ruby/gems/<Layout::API>/gems/<name>-<version>, which
    # `zr-dev vendor` writes). It comes before ruby's own library on the
    # load path, as rubygems activates an installed gem over a default gem.
    # One with `vendored: false` has its Ruby half in ruby's own library at the
    # same version (psych, openssl), or has no Ruby half (zlib).
    #
    # Some versions are newer than the ones that the pinned ruby ships:
    # docs/reference/differences-from-ruby.md lists them.
    module Ports
      # One port: the gem's version, the versions whose C interface the port
      # implements (rubygems requirements, joined with ", ", read only when
      # a build selects another version of the gem; Ports.requirement),
      # whether vendor/ holds the gem, and whether a build for this host
      # links the gem's own C extension in place of the port (`c_first`,
      # lib/zr/ext.rb): the port then serves only where that C cannot run
      # or build (wasm, another target with no toolchain, a ruby that lacks
      # the gem) and the compiler that eval support carries.
      # @rbs skip -- typed in sig/zr/library/ports.rbs
      Port = Data.define(:version, :compat, :vendored, :c_first)

      #: (String version, ?compat: String, ?vendored: bool, ?c_first: bool) -> Port
      def self.port(version, compat: "~> #{version}", vendored: true, c_first: false)
        Port.new(version: version, compat: compat, vendored: vendored, c_first: c_first)
      end

      ALL = {
        # A gem in vendor/, over a port in lib/zr/runtime/ext.
        "prism" => port("1.9.0"),
        # json 2.20 and 2.21 have 3.0's C interface; the port acts as 2.x
        # where 2.x deprecates what 3.0 refuses (ext/json/ext).
        "json" => port("3.0.2", compat: ">= 2.20, < 3.1", c_first: true),
        # psych and openssl keep their ports first: their own C loads a
        # dylib that is not the system's (libyaml, libssl), which a binary
        # cannot carry.
        "psych" => port("5.5.0", vendored: false),
        "bigdecimal" => port("4.1.3"),
        "digest" => port("3.3.0", vendored: false, c_first: true),
        "syslog" => port("0.4.0"),
        "ffi" => port("1.17.4"),
        "openssl" => port("4.0.2", vendored: false),
        "nkf" => port("0.3.0"),
        "fiddle" => port("1.1.8"),
        "racc" => port("1.8.1"),
        "debug" => port("1.11.1"),
        "rbs" => port("4.2.0"),
        # The C of the pinned ruby's default gem, in lib/zr/runtime/ext. Its Ruby half,
        # if any, is ruby's own at the same version.
        "date" => port("3.6.0", vendored: false, c_first: true),
        "stringio" => port("3.2.1.dev", vendored: false, c_first: true),
        "strscan" => port("3.1.9.dev", vendored: false, c_first: true),
        # zlib keeps its port first: its own C inflates without the GVL,
        # and a thread killed there corrupts the heap (W9a).
        "zlib" => port("3.2.4", vendored: false),
        "io-console" => port("0.9.4", vendored: false, c_first: true),
        "etc" => port("1.5.0", vendored: false, c_first: true),
        "fcntl" => port("1.3.0", vendored: false)
      }.freeze #: Hash[String, Port]

      # The rubygems requirement of a port's `compat`.
      #: (String compat) -> Gem::Requirement
      def self.requirement(compat) = Gem::Requirement.new(*compat.split(", "))

      # The lib directory of each gem that vendor/ holds, in the order a
      # require searches them.
      #: () -> Array[String]
      def self.roots = ALL.filter_map { |name, port| lib(name, port.version) if port.vendored }

      # The lib directory of port `name` in vendor/.
      #: (String name, ?String version) -> String
      def self.lib(name, version = ALL.fetch(name).version) = File.join(Layout.gem_root(name, version), "lib")
    end
  end
end
