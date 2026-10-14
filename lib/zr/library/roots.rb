# frozen_string_literal: true

require_relative "../paths"
require_relative "../session"
require_relative "../config"
require_relative "../target"
require_relative "layout"
require_relative "ports"
require_relative "stdlib"

module Zr
  module Library
    # The directories that a program's `require` reads, and the names that
    # the loader treats as part of the runtime. The directories: the pinned
    # ruby's own library and bundled gems as a stock ruby installs them, in
    # vendor/ruby (`zr-dev vendor` writes it, tool/lib/zr/dev/vendored.rb). zr
    # compiles their files into the program, and never loads them itself. A
    # build reads no gem of the host, so it needs no gem but zr, and two
    # machines build the same bytes.
    #
    # The gems with a C part are zr's own (lib/zr/library/ports.rb).
    module Roots
      # The name of the kernel's description (`Runtime#carried_text`), which
      # `require "zr_description"` finds. No file has it: the loader takes
      # its source from the runtime. So the name is the same in every
      # checkout and cache, and a compiler that zr builds does not carry
      # where its cache was. It is part of the runtime, as its kernel is.
      DESCRIPTION = "<zr>/zr_description.rb"

      # The name of the ruby switches' prelude (`Hir::Switches#prelude`).
      # No file has it either: the build gives its text. It is part of
      # the runtime, so it can write the globals that ruby makes read-only.
      SWITCHES = "<zr>/ruby_switches.rb"

      # The compiler that a program with eval links in, and the
      # tree-walking interpreter for a program that cannot write machine
      # code into itself. Both contain the same front end. `Zr::Eval`
      # gives the back end that each one runs.
      EVAL_COMPILER = File.expand_path("../eval.rb", __dir__) #: String
      EVAL_INTERPRETER = File.expand_path("../eval/interpreter.rb", __dir__) #: String

      module_function

      # The directory of ruby's own library and the default gems.
      #: () -> String
      def pure = upstream.first

      # The lib directory of each bundled gem, in Stdlib::BUNDLED's order,
      # each in its own directory, as ruby installs them.
      #: () -> Array[String]
      def bundled_roots = upstream.last

      # The lib directory of the bundled gem `name`.
      #: (String name) -> String
      def lib_of(name) = bundled_roots.fetch(Stdlib::BUNDLED.keys.index(name) || raise(KeyError, "no bundled gem #{name}"))

      # `[pure, bundled_roots]`.
      #: () -> [String, Array[String]]
      def upstream
        Session.current.memo(:library_roots) do
          carried || [Layout::RUBYLIBDIR, Stdlib::BUNDLED.map { |name, version| File.join(Layout.gem_root(name, version), "lib") }]
        end
      end

      # A program that includes the compiler uses the directories from its
      # build, because it can run on a machine with no zr. Only a build
      # with eval support writes them (`LoadTables`). Other compiled
      # compilers find vendor/ruby beside themselves.
      #: () -> [String, Array[String]]?
      def carried
        return nil unless Binary.running? && defined?(::Zr::Eval::Runtime)

        from_load_names(::Zr::Eval::Runtime.library_roots)
      end

      # `[pure, bundled_roots]` from the roots line of the load tables
      # (`LoadTables#texts`): the native roots, an empty line, then the
      # GemSet's roots and the rest of `stdlib`, which ends with ruby's
      # library and the bundled gems. nil when the line has no such part.
      #: (Array[String] names) -> [String, Array[String]]?
      def from_load_names(names)
        later = names.drop((names.index("") || return) + 1)
        count = Stdlib::BUNDLED.size
        later.size > count ? [later[-count - 1], later.last(count)] : nil
      end

      # The library roots for `target`, in search order. zr's own code
      # comes first: the OS layer's native parts and tables, then the
      # portable ones, then zr's own libraries. A file there replaces an upstream file of the same
      # name (an overlay, which names the file it replaces). Then the port gems,
      # which win over ruby's own copies as an installed gem wins over a
      # default gem (json 3.0.2, not 2.18.0), then ruby's own library,
      # then the bundled gems in their own directories.
      #: (?Target target) -> Array[String]
      def stdlib(target = Target.default)
        Session.current.memo([:stdlib, target.triple]) { [Layout.ext_os(target), Layout::EXT, Layout::RUNTIME_LIB, *Ports.roots, pure, *bundled_roots].freeze }
      end

      # The roots of zr's ports of C: the OS layer, the portable native
      # parts, and the port gems. A require at run time searches them
      # before $LOAD_PATH, so a host gem's copy, whose C no binary here can
      # load, never shadows them. Every other root comes after $LOAD_PATH,
      # as ruby's own library does.
      #: (?Target target) -> Array[String]
      def native(target = Target.default) = [Layout.ext_os(target), Layout::EXT, *Ports.roots]

      #: (String file) -> bool
      def runtime_file?(file) = File.expand_path(file).start_with?("#{Paths::RUNTIME}/") || given?(file)

      # Whether `file` is Ruby in place of ruby's C: the core library or
      # an extension's C half (ext/).
      #: (String file) -> bool
      def stands_in_for_c?(file) = File.expand_path(file).start_with?("#{Paths::RUNTIME}/core/", "#{Layout::EXT}/")

      #: (String file) -> bool
      def description?(file) = file == DESCRIPTION

      # A file whose text the build gives, not a directory: the kernel's
      # description or the switches' prelude.
      #: (String file) -> bool
      def given?(file) = file == DESCRIPTION || file == SWITCHES

      # Gives the source of the kernel's description of `target` when a
      # file requires `zr_description`: only eval support and a program
      # that compiles itself do. Nil where no runtime is loaded (an eval
      # in a binary).
      #: (Target target) -> ^() -> String?
      def description(target) = -> { Zr::Runtime.for(target).carried_text if Zr.const_defined?(:Runtime, false) }

      # A file of the runtime's libraries (Layout::EXT, Layout::RUNTIME_LIB): it is
      # internal, as the core is, so a backtrace shows its methods as
      # builtins.
      #: (String file) -> bool
      def internal_library?(file) = file.start_with?("#{Layout::EXT}/", "#{Layout::RUNTIME_LIB}/") || given?(file)

      # The eval support file for `target`. `ZR_EVAL=walk` selects the
      # tree-walking interpreter where the eval compiler (JIT) could run.
      # The tests use this to check the interpreter against the JIT.
      #: (?Target target) -> String
      def eval_file(target = Target.default)
        target.jits? && !Config.current.eval_walk? ? EVAL_COMPILER : EVAL_INTERPRETER
      end
    end
  end
end
