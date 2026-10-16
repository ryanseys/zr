# frozen_string_literal: true

# `Hir::Build`'s preludes: the files that a program gets ahead of its
# main file (rubygems, rbconfig, the eval support), and the eval calls
# that decide them.

module Zr
  module Hir
    class Build
      # `DATA`, which ruby defines before the first line of a main file
      # that has an `__END__` line: a File at the byte after that line.
      #: (Unit main, Integer? at) -> ConstWrite
      def self.data(main, at)
        made = Send.of(Core.new(:File, 0), :data, [Literal.new(main.source, 0), Literal.new(at, 0), Literal.new(Paths.shown(main.file), 0)], 0)
        ConstWrite.new(nil, :DATA, made, 0)
      end

      # Each prelude whose loader flag is set, in the program's load
      # order: rbconfig before the gems that read it, and the compiler
      # before all that a compile at run time can reach.
      #
      # A prelude is read when it is taken, and it can set another flag
      # (`irb_session` requires irb, which requires fileutils, which
      # evals). So the table is walked again until a walk takes nothing.
      # The result is in table order, not in the order that the flags
      # were set.
      #: (Loader loader, Target target) -> Array[node]
      def self.preludes(loader, target)
        asking = {
          configures?: -> { [rbconfig(loader)] },
          evals?: -> { [eval_require(loader, target)] },
          gems?: -> { rubygems(loader) },
          lazy_gems?: -> { gem_autoloads },
          normalizes?: -> { [normalizer(loader)] },
          pretty_prints?: -> { [pretty_printer(loader)] },
          irbs?: -> { [irb_session(loader)] },
          asts?: -> { [ast_translator(loader)] },
          ruby_prisms?: -> { ruby_prism(loader) }
        } #: Hash[Symbol, ^() -> Array[node]]
        taken = {} #: Hash[Symbol, Array[node]]
        while (flag = asking.each_key.find { |name| !taken.key?(name) && loader.public_send(name) })
          taken[flag] = asking.fetch(flag).call
        end
        asking.each_key.flat_map { |flag| taken.fetch(flag, []) }
      end

      # Only the compiler, as the units of eval support. The loader built
      # them, and its flags tell what else a program that links them in
      # needs. Eval support also contains the preludes (rbconfig, the
      # normalizer, the pretty printer, the syntax tree translator): a
      # program with eval can need any of them, and here they are lowered
      # once, not with each such program.
      # The compiler never loads error_highlight (lib/zr/hir/spots.rb) or
      # timeout (only prism's ruby_parser translation requires it), so
      # their requires wait for run time. Else their files would be hidden
      # units, and a program that requires one would link in that copy,
      # whose sends find the core's own methods, not the program's.
      #: (?Target target) -> Loader
      def self.eval_support(target = Target.default)
        Loader.new(Library::Roots.stdlib(target), description: Library::Roots.description(target),
                                                  deferred: %w[error_highlight timeout]).tap do |loader|
          eval_require(loader, target)
          rubygems(loader)
          loader.add(LAZY_RUBYGEMS)
          rbconfig(loader)
          normalizer(loader)
          pretty_printer(loader)
          irb_session(loader)
          ast_translator(loader)
        end
      end

      # rubygems and bundled_gems, which ruby loads before a program's
      # first line. A zr program loads them at boot if one of its files
      # uses Gem or Bundler, calls `gem` or requires rubygems. Its
      # compiler then already contains them.
      #: () -> Array[String]
      def self.rubygems_files = %w[rubygems bundled_gems].map { |name| File.join(Library::Roots.pure, "#{name}.rb") }
      #: () -> Array[String]
      def self.ahead = [File.join(Library::Roots.pure, "rubygems"), *rubygems_files]
      # The files of rubygems' autoloads that its boot reads.
      #: () -> Array[String]
      def self.booted = %w[dependency path_support requirement util version].map { |name| File.join(Library::Roots.pure, "rubygems/#{name}.rb") }

      # The file that loads rubygems, bundled_gems and the gem manifest as
      # the prelude does. Eval support carries it and the files it requires.
      LAZY_RUBYGEMS = File.join(Library::Layout::RUNTIME_LIB, "zr/rubygems.rb") #: String

      # The constants that rubygems defines as it loads, which the
      # program's other preludes do not define already.
      LAZY_GEM_NAMES = %i[Gem RUBYGEMS_ACTIVATION_MONITOR].freeze

      # ruby loads rubygems before a program's first line, so every file can
      # use Gem. A zr program loads it as it boots only when one of its files
      # uses Gem (`rubygems`). A program that compiles at run time can reach
      # a file that uses Gem, so there each of LAZY_GEM_NAMES is an
      # autoload of LAZY_RUBYGEMS, and the program pays for rubygems' boot
      # only when it uses one. The main file makes the autoloads, as the
      # program would: one that a runtime file made would hide the name
      # from the program.
      #: () -> Array[node]
      def self.gem_autoloads
        LAZY_GEM_NAMES.map do |name|
          Send.of(Core.new(:Object, 0), :autoload, [Literal.new(name, 0), Literal.new("zr/rubygems", 0)], 0)
        end
      end

      # After them, the file that gives rubygems the program's gems, as
      # bundler's setup does.
      GEM_MANIFEST = File.join(Library::Layout::RUNTIME_LIB, "zr/gem_manifest.rb") #: String

      #: (Loader loader) -> Array[Require]
      def self.rubygems(loader)
        rubygems_files.map { |path| Require.new(:require, File.basename(path, ".rb"), path, loader.add(path), 0) } <<
          Require.new(:hidden, "zr/gem_manifest", GEM_MANIFEST, loader.add(GEM_MANIFEST), 0)
      end

      # The file that arms String#unicode_normalize's load of ruby's own
      # normalize.rb. It is a runtime file, so it is not in
      # $LOADED_FEATURES. The load that it arms (at the first call) is.
      NORMALIZER = File.join(Library::Layout::RUNTIME_LIB, "zr/normalizer.rb") #: String

      #: (Loader loader) -> Require
      def self.normalizer(loader)
        Require.new(:hidden, "zr/normalizer", NORMALIZER, loader.add(NORMALIZER), 0)
      end

      # The file that arms Kernel#pp's load of ruby's own pp.rb, as
      # CRuby's prelude requires it on the first call.
      PRETTY_PRINTER = File.join(Library::Layout::RUNTIME_LIB, "zr/pretty_printer.rb") #: String
      IRB_SESSION = File.join(Library::Layout::RUNTIME_LIB, "zr/irb_session.rb") #: String
      SYNTAX_TREE = File.join(Library::Layout::RUNTIME_LIB, "zr/syntax_tree.rb") #: String

      # The file that loads RubyVM::AbstractSyntaxTree's translator. A
      # program that uses the module loads it before its body. Both are
      # not in $LOADED_FEATURES.
      #: (Loader loader) -> Require
      def self.ast_translator(loader)
        Require.new(:hidden, "zr/syntax_tree", SYNTAX_TREE, loader.hidden(SYNTAX_TREE), 0)
      end

      # Ruby::Prism is an autoload of ruby/prism (core/box.rb). A program
      # that uses it, or a #syntax_tree, includes the file, which the
      # first read of the constant loads.
      #: (Loader loader) -> Array[node]
      def self.ruby_prism(loader)
        path = loader.resolve(:require, "ruby/prism", Library::Layout::EXT) or raise ArgumentError, "no ruby/prism.rb in the library roots"
        loader.add(path)
        []
      end

      #: (Loader loader) -> Require
      def self.pretty_printer(loader)
        Require.new(:hidden, "zr/pretty_printer", PRETTY_PRINTER, loader.add(PRETTY_PRINTER), 0)
      end

      # The messages that irb loads for its locale. irb finds this file by
      # a search of $LOAD_PATH, and reads the first match. A zr program
      # contains its files and has no directory to search. So the program
      # includes it: added and not required, because irb loads it and a
      # load does not change $LOADED_FEATURES.
      #: () -> String
      def self.irb_messages = File.join(Library::Roots.lib_of("irb"), "irb/lc/error.rb")

      # The file that arms Binding#irb's load of irb, as CRuby's prelude
      # requires it on the first call.
      #: (Loader loader) -> Require
      def self.irb_session(loader)
        loader.add(irb_messages)
        Require.new(:hidden, "zr/irb_session", IRB_SESSION, loader.add(IRB_SESSION), 0)
      end

      # `rbconfig`, which ruby loads before a program's first line
      # (rubygems requires it at boot). A zr program includes it if one of
      # its files uses `RbConfig` or requires it. So the constant exists
      # and `require "rbconfig"` returns false, as in ruby.
      #: (Loader loader) -> Require
      def self.rbconfig(loader)
        path = loader.resolve(:require, "rbconfig", Library::Layout::EXT) #: String
        Require.new(:require, "rbconfig", path, loader.add(path), 0)
      end

      # A require of eval support, before all other code of the program.
      # Only a program that uses eval links in the compiler, so a program
      # without eval links nothing more. The program did not require it,
      # so what it loads is not in $LOADED_FEATURES.
      #: (Loader loader, ?Target target) -> Require
      def self.eval_require(loader, target = Target.default)
        path = Library::Roots.eval_file(target)
        Require.new(:hidden, "zr/eval", path, loader.hidden(path), 0)
      end

      # The sends that call the method given by a leading Symbol, and the
      # fetches that return it for a later call.
      SENDS = %i[send __send__ public_send].freeze
      FETCHES = %i[method public_method instance_method].freeze

      # The method name that a send or a fetch takes as its first
      # argument, when that is a literal: a Symbol, or a String, which the
      # call turns into one.
      #: (untyped arg) -> Symbol?
      def self.literal_name(arg)
        case (value = arg.value if arg.is_a?(Literal) || arg.is_a?(FrozenString))
        when Symbol then value
        when String then value.to_sym
        end
      end

      # Whether a call of `name` with `argc` arguments compiles ruby that
      # runs in the caller's frame. `named` is the first argument if it is
      # a literal Symbol, so the check sees through a send or a fetch to
      # the method.
      #
      # This result has two uses. A program with such a call links in the
      # compiler. And the enclosing method arms the catch for a `return`
      # in the source, because that return belongs to the method, not to
      # the eval.
      #: (Symbol? name, ?named: Symbol?, ?argc: Integer) -> bool
      def self.eval_call?(name, named: nil, argc: 0)
        return eval_call?(named, argc: argc - 1) if named && SENDS.include?(name)
        # The call comes later, with arguments this site cannot see.
        return named == :eval || STRING_EVALS.include?(named) if named && FETCHES.include?(name)

        name == :eval || (STRING_EVALS.include?(name) && argc.positive?)
      end
    end
  end
end
