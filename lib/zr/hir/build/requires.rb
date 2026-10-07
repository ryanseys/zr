# frozen_string_literal: true

# `Hir::Build`'s requires and autoloads of a feature that is known at
# compile time.

module Zr
  module Hir
    class Build
      # The calls that load a file. A send of one of them with a computed
      # name can find a file that was not compiled in, and then the
      # program links in the compiler to compile that file at run time.
      REQUIRES = %i[require require_relative load].freeze

      # A require's name at compile time: a String literal, or a path built
      # from `__dir__` with a literal.
      #: (untyped node) -> String?
      def literal_feature(node)
        args = node.arguments&.arguments
        return nil unless args&.size == 1

        args[0].is_a?(Prism::StringNode) ? args[0].unescaped : @loader.literal_path(args[0], @file)
      end

      # The features that ruby loads before a program starts, so a require
      # of one returns false. The runtime's gem prelude loads
      # error_highlight, did_you_mean and syntax_suggest's core extension,
      # as ruby's does. Ruby 4.0.7 also loads rubygems, which this runtime
      # does not preload: a require of it stops with a message, and does
      # not return false and then fail at the first use. Only pathname's C
      # part is loaded, so `require "pathname"` still runs its Ruby part
      # and returns true.
      GEM_PRELOADED = %w[error_highlight did_you_mean syntax_suggest/core_ext].freeze
      PRELOADED = (%w[enumerator thread fiber rational complex ruby2_keywords set monitor rbconfig enc/encdb enc/trans/transdb] +
                   GEM_PRELOADED).freeze

      # ruby's encoding and transcoder extensions, which this runtime has
      # built in. A require of one stays for the run time, where the core
      # answers it as ruby does: true the first time, then false
      # (`Kernel.builtin_extension`).
      ENCODINGS = %r{\Aenc/}

      # prism and its files, which zr's own ports require.
      INTERNAL_PRISM = %r{\Aprism(?:/|\z)}

      # The ruby features that no library root here contains, and that
      # ruby did not load before the program. A require of one stops with
      # a message.
      #: (?Target target) -> Array[String]
      def self.missing_features(target = Target.default)
        missing = @missing_features ||= {} #: Hash[String, Array[String]]
        missing[target.triple] ||= FEATURES.reject do |feature|
          PRELOADED.include?(feature) || Library::Roots.stdlib(target).any? { |root| File.file?(File.join(root, "#{feature}.rb")) }
        end.sort.freeze
      end

      # A feature ruby loaded before the program, by any of its names:
      # `thread`, `thread.rb` and `enumerator.so` all count.
      #: (String? feature) -> bool
      def preloaded?(feature)
        (@loader ? @loader.preloaded : PRELOADED).include?(feature.to_s.sub(/\.(?:rb|so|bundle)\z/, ""))
      end

      # A require of a literal name resolves at compile time: the file
      # becomes a unit of the program. A ruby feature that no root here
      # contains stops with a message. Every other name raises LoadError
      # when it runs, as in ruby.
      #: (Prism::CallNode node) -> node
      def require_node(node)
        line = node.location.start_line
        # `call` makes this node only for a literal feature.
        feature = literal_feature(node) #: String
        if node.name == :require && %w[rubygems bundled_gems].include?(feature.to_s.delete_suffix(".rb")) && !@loader.ahead?(@file) &&
           (@loader.own?(@file) || @loader.gem_file?(@file)) &&
           @loader.boots_gems?
          # The prelude loaded rubygems as the program booted.
          gems!(:Gem)
          return Literal.new(false, line)
        end
        if node.name == :require && preloaded?(feature)
          @loader.configures! if feature.to_s.delete_suffix(".rb") == "rbconfig"
          return Literal.new(false, line)
        end

        return plain_call(node, compiles: false) if @loader.deferred?(feature) || (@in_def && @loader.ahead?(@file))
        return plain_call(node, compiles: false) if node.name == :require && FEATURES.include?(feature.to_s.delete_suffix(".so")) && feature.match?(ENCODINGS)

        path = @loader.resolve(node.name, feature, @file)
        gem_refusal(node, feature, path)
        stop = path.nil? && node.name != :require_relative && stop_for(node, feature) #: Stop | false | nil
        return stop if stop

        # No file found: the call searches at run time, in the $LOAD_PATH
        # that the program has then. The build never uses the host's
        # rubygems for a gem with the feature. A binary contains only what
        # zr vendors and what the program's own roots contain, so the same
        # source builds the same bytes on any machine.
        unless path
          gate!(node, feature)
          # ruby's load of a bare name falls back to the working directory
          # it runs in (a settings file beside the binary), so the program
          # carries the compiler to read it, unless the build is gated.
          @loader.compiles_at_run_time! if node.name == :load && !@loader.gated?
          return plain_call(node, compiles: false)
        end

        # After a $LOAD_PATH change the compiler cannot follow, a library
        # name is searched for at run time, as ruby searches: the file
        # stays compiled in, and the search uses it unless a directory the
        # program added has one of that name.
        if node.name == :require && @loader.load_path_computed? && !feature.start_with?("/", "./", "../", "~") && @loader.own?(@file)
          @loader.add(path)
          return plain_call(node, compiles: false)
        end

        # zr's own ports use prism where ruby's C uses parse.y (ripper.so,
        # RubyVM::AbstractSyntaxTree). ruby loads no Prism for them, so
        # prism loads hidden, as eval support's does, until the program
        # requires it itself.
        if node.name == :require && feature.match?(INTERNAL_PRISM) && Library::Roots.runtime_file?(@file)
          return Require.new(:hidden, feature, path, @loader.hidden(path), line)
        end

        # A file that the program's own file reaches by its path is the
        # program's too; one that a root gives is a library's.
        @loader.own!(path) if @loader.own?(@file) && (node.name != :require || feature.to_s.start_with?("/", "./", "../", "~"))

        # A require in a file that only eval support loads belongs to the
        # compiler. The runtime knows this at run time, so one unit serves
        # eval support and a program that requires the same file.
        Require.new(node.name, feature, path, @loader.add(path), line)
      end

      # A literal require in the program's own file that no root has stays
      # for the run time, as in ruby: it raises LoadError only if it runs,
      # so one in a branch that never runs costs nothing. With the gate
      # (the CLI's, without --allow-runtime-require) the binary has no
      # compiler to compile a file it finds then, and `zr build` says so.
      # A require that a `rescue LoadError` guards is quiet, as is one in a
      # library's file: code there can handle the LoadError.
      #: (Prism::CallNode node, String? feature) -> void
      def gate!(node, feature)
        return unless @loader.gated? == :warn && @loader.own?(@file) && @guarded.to_i.zero?

        name = feature.to_s.delete_suffix(".rb")
        fix = if node.name == :require && !name.start_with?("/", ".", "~")
                "give --gem #{name.split("/").first}=<dir> or a --gemfile that has it"
              else
                "add the file"
              end
        warn "zr: warning: #{@file}:#{node.location.start_line}: cannot load such file -- #{name}; the #{node.name} raises " \
             "LoadError if it runs. To load it, #{fix}, or build with --allow-runtime-require"
      end

      # A require that reaches a file of a gem that zr cannot compile
      # (`GemSet#refusal`) stops the build at the require's line. A gem
      # whose C extension zr does not port (`GemSet::Entry#native`) is
      # compiled but for that part: the build says so once, and a require
      # of the C part, which no root holds, raises LoadError if it runs, as
      # it does in a ruby where the extension did not build.
      #: (Prism::CallNode node, String? feature, String? path) -> void
      def gem_refusal(node, feature, path)
        gem = @loader.refused_gem(path, (feature unless node.name == :require_relative))
        return unless gem
        return @loader.native_gem!(gem) if gem.native

        refuse(node, "require of #{feature.to_s.inspect}: #{gem.refusal}")
      end

      # The reason that a ruby library is not here, when the reason is a
      # decision and not a gap. The stop message is "<reason> is not
      # implemented yet" (`zr_unloadable`), so each value completes that
      # sentence.
      UNSUPPORTED_LIBRARIES = {
        "mkmf" => "mkmf, which writes a C extension's Makefile: zr compiles no C, so an extension it configured",
        "prism/ffi" => "prism/ffi, the FFI half of prism: this runtime's prism is a Ruby port of the C, so the C half"
      }.freeze

      # A ruby feature that this runtime has no file for. The stop occurs
      # only when the program runs the require, so a guarded require that
      # never runs costs nothing.
      #: (Prism::CallNode node, String? feature) -> Stop?
      def stop_for(node, feature)
        name = feature.to_s.delete_suffix(".rb")
        return unless FEATURES.include?(name)

        line = node.location.start_line
        @loader&.stopped&.push(name)
        Stop.new(UNSUPPORTED_LIBRARIES[name] || "#{node.name} of #{feature.inspect}", line)
      end

      #: (untyped node) -> boolish
      def literal_autoload?(node)
        args = node.arguments&.arguments
        args&.size == 2 && args[0].is_a?(Prism::SymbolNode) && (args[1].is_a?(Prism::StringNode) || @loader.literal_path(args[1], @file))
      end

      # `autoload :Name, "feature"` resolves the feature as a require
      # does, so the file is a unit of the program.
      #: (untyped node) -> Autoload
      def autoload_node(node)
        line = node.location.start_line
        name_node, path_node = node.arguments.arguments
        # `literal_autoload?` makes sure that the feature is known.
        feature = path_node.is_a?(Prism::StringNode) ? path_node.unescaped : @loader.literal_path(path_node, @file) #: String
        # A feature that is already loaded gets no autoload entry, as in
        # ruby: `require` would return false and read no file, so
        # `Object.autoload?(:Set)` is nil after `autoload :Set, "set"`. The
        # name is still declared, which is visible on any module except
        # Object: `M.constants` lists it, and the constant is undefined
        # there (not read from an outer scope).
        #
        # With no entry, the loader does not expect a file at run time,
        # which is the only case that needs the compiler. Otherwise
        # `autoload :Set, "set"` would add the compiler (44 MB) for a
        # declaration that reads nothing.
        return Autoload.new(node.receiver && expr(node.receiver), name_node.unescaped.to_sym, feature, feature, nil, line,
                            true) if preloaded?(feature)

        path = @loader.resolve(:require, feature, @file)
        gem_refusal(node, feature, path)
        # An autoload that the gem prelude's boot does not read leaves its
        # file to the program that reads the constant.
        return Autoload.new(node.receiver && expr(node.receiver), name_node.unescaped.to_sym, path || feature, path || feature, nil, line) if path && @loader.ahead?(@file) && !@loader.booted?(path)

        stop = path.nil? && stop_for(node, feature)
        unit = stop ? @loader.stop_unit(stop.what, line) : (path && @loader.add(path))
        # No root contains the file: the first read requires the feature
        # from the $LOAD_PATH that the program has then.
        @loader.compiles_at_run_time! unless unit
        Autoload.new(node.receiver && expr(node.receiver), name_node.unescaped.to_sym, feature, path || feature, unit, line)
      end
    end
  end
end
