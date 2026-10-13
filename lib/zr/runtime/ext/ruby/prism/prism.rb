# frozen_string_literal: true

# Init_prism of ruby's own prism (prism/extension.c, built for the
# Ruby::Prism namespace): Ruby::Prism's singleton methods and constants,
# over zr's Ruby port of prism's C. The port makes the prism gem's objects
# (lib/zr/runtime/ext/prism), which load hidden: a program that did not
# require prism has no Prism. Each result is then made again of
# Ruby::Prism's classes (Prism::Ruby::Import). Each method reads the
# hidden Prism, so it runs as the runtime's own code.
require "prism"
require "prism/ruby/import"

module Ruby::Prism
  class << self
    def lex(source, **options) = imported(:lex, source, options)
    def lex_file(filepath, **options) = imported(:lex_file, filepath, options)
    def parse(source, **options) = imported(:parse, source, options)
    def parse_file(filepath, **options) = imported(:parse_file, filepath, options)
    def profile(source, **options) = imported(:profile, source, options)
    def profile_file(filepath, **options) = imported(:profile_file, filepath, options)
    def parse_stream(stream, **options) = imported(:parse_stream, stream, options)
    def parse_comments(source, **options) = imported(:parse_comments, source, options)
    def parse_file_comments(filepath, **options) = imported(:parse_file_comments, filepath, options)
    def parse_lex(source, **options) = imported(:parse_lex, source, options)
    def parse_lex_file(filepath, **options) = imported(:parse_lex_file, filepath, options)
    def parse_success?(source, **options) = imported(:parse_success?, source, options)
    def parse_failure?(source, **options) = imported(:parse_failure?, source, options)
    def parse_file_success?(filepath, **options) = imported(:parse_file_success?, filepath, options)
    def parse_file_failure?(filepath, **options) = imported(:parse_file_failure?, filepath, options)
    def dump(source, **options) = imported(:dump, source, options)
    def dump_file(filepath, **options) = imported(:dump_file, filepath, options)

    private

    # The port's answer to `name`, made of Ruby::Prism's classes.
    def imported(name, input, options)
      Primitive.attr! :hidden
      result = begin
        ::Prism.public_send(name, input, **port_options(options))
      rescue ::Prism::CurrentVersionError
        # extension.c raises its own namespace's error.
        raise CurrentVersionError, RUBY_VERSION
      end
      ::Prism.const_get(:Ruby).const_get(:Import).call(result, self)
    end

    # The options as the port reads them: a Ruby::Prism::Scope is the
    # scope type here, as rb_cPrismScope is in ruby's build, and the gem's
    # Prism::Scope is not.
    def port_options(options)
      Primitive.attr! :hidden
      scopes = options[:scopes]
      return options unless scopes.is_a?(Array)

      options.merge(scopes: scopes.map do |scope|
        case scope
        when Scope then ::Prism::Scope.new(scope.instance_variable_get(:@locals), scope.instance_variable_get(:@forwarding))
        when ::Prism::Scope then raise TypeError, "wrong argument type #{scope.class} (expected Array or Prism::Scope)"
        else scope
        end
      end)
    end
  end

  class StringQuery
    class << self
      def local?(string) = query(:local?, string)
      def constant?(string) = query(:constant?, string)
      def method_name?(string) = query(:method_name?, string)

      private

      def query(name, string)
        Primitive.attr! :hidden
        ::Prism::StringQuery.public_send(name, string)
      end
    end
  end
end

module Ruby::Prism
  # EXPECTED_PRISM_VERSION: the port's, as the gem's half has it.
  def self.port_version
    Primitive.attr! :hidden
    ::Prism::VERSION
  end
  VERSION = port_version
  singleton_class.send(:remove_method, :port_version)
end
