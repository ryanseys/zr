# frozen_string_literal: false
#
# This file is intentionally NOT frozen-literal. Real rbconfig's values are
# mutable strings (`RbConfig::CONFIG["cflags"].frozen?` is false in CRuby),
# and both `RbConfig.expand` and mkmf's `init_mkmf` write THROUGH them with
# `String#replace`. A frozen literal here is a `FrozenError` before any
# extension is configured.
#
# zr's own `rbconfig`. Ruby generates this file at build time from its
# build configuration; zr has no such build, so the facts come from the
# running program instead. It contains the keys that rubygems and bundler
# read: version, platform, and the install layout.
#
module RbConfig
  # rbconfig.rb is Ruby in CRuby as well, so its methods show their
  # parameters and frames as Ruby methods do.
  Primitive.attr! :ruby

  # The name of ruby's library directories (core/ruby_version.rb), and
  # the major and minor version that the API, its library and its pkg-config
  # file are named for.
  ruby_version = Primitive.zr_hidden_get(Kernel, :__zr_ruby_lib_version__).dup
  major, minor, teeny = RUBY_VERSION.split(".")
  api = "#{major}.#{minor}"

  # The platform facts are the running program's own. `RUBY_PLATFORM` is
  # `<cpu>-<os>`; the rest follow from it. `dup`, because a value here has
  # to stay mutable -- see the note above.
  arch = RUBY_PLATFORM.dup
  host_cpu, os = arch.split("-", 2)
  darwin = os.start_with?("darwin")
  # A glibc ruby reports `host_os` `linux-gnu` beside `arch` `x86_64-linux`;
  # a musl one (`aarch64-linux-musl`) and a Darwin one report the same
  # token in both.
  host_os = os == "linux" ? "linux-gnu" : os
  vendor = darwin ? "apple" : (os == "linux" ? "pc" : "unknown")
  triple = "#{host_cpu}-#{vendor}-#{host_os}"
  # A C extension is a BUNDLE on Darwin and a shared object everywhere else.
  dlext = darwin ? "bundle" : "so"
  soext = darwin ? "dylib" : "so"
  ldshared = darwin ? "clang -dynamic -bundle" : "cc -shared"
  # The two linkers spell `DLDFLAGS` differently -- see the key below.
  undefined_flag = darwin ? "-Wl,-undefined,dynamic_lookup" : "-Wl,--allow-shlib-undefined"

  # The install layout is the one that the program found at start
  # (core/env.rb): ZR_PREFIX, else the home of the zr that runs it (its
  # vendored ruby tree, which has an installed ruby's layout), else a
  # directory under the home directory that zr owns, which rubygems can
  # create. It is never the layout of the ruby that compiled the program:
  # a binary contains nothing read from the machine that built it, so the
  # same source builds the same bytes anywhere. A home that zr cannot
  # write is no problem: rubygems then installs to Gem.user_dir, as it
  # does for a system ruby.
  prefix = Primitive.zr_hidden_get(ENV, :__zr_prefix__).dup
  zr_home = Primitive.zr_hidden_get(ENV, :__zr_home__)

  # Where MRI's headers live for a C extension build. zr builds no C
  # extension yet, so these name the cache a later one would fill.
  hdrdir = ENV["ZR_CEXT_HDRDIR"] || "#{prefix}/include/ruby-#{ruby_version}"
  archhdrdir = ENV["ZR_CEXT_ARCHHDRDIR"] || "#{hdrdir}/#{RUBY_PLATFORM}"

  # `RbConfig.ruby` is `bindir` plus `ruby_install_name`, and rubygems
  # spawns exactly that string. The interpreter is zr: under a zr home
  # (`<zr>/vendor/ruby`) it is `<zr>/exe/zr`.
  zr_bindir = ENV["ZR_BINDIR"] || (zr_home && !ENV["ZR_PREFIX"] ? File.expand_path("../../exe", zr_home) : "#{prefix}/bin")
  zr_ruby_name = ENV["ZR_RUBY_INSTALL_NAME"] || "zr"

  # The staging root of `make install`, empty for an installed ruby.
  DESTDIR = ""

  CONFIG = {
    "DESTDIR" => DESTDIR,
    "MAJOR" => major,
    "MINOR" => minor,
    "TEENY" => teeny,
    "PATCHLEVEL" => RUBY_PATCHLEVEL.to_s,
    "ruby_version" => ruby_version,
    "RUBY_SO_NAME" => "ruby.#{api}",
    "ruby_install_name" => zr_ruby_name,
    "RUBY_INSTALL_NAME" => zr_ruby_name,
    "RUBY_BASE_NAME" => "ruby",

    # Platform / host triple.
    "arch" => arch,
    "sitearch" => arch,
    "platform" => triple,
    "host" => triple,
    "host_alias" => "",
    "host_cpu" => host_cpu,
    "host_vendor" => vendor,
    "host_os" => host_os,
    "target" => triple,
    "target_cpu" => host_cpu,
    "target_vendor" => vendor,
    "target_os" => host_os,

    # Executable / shared-object extensions.
    "EXEEXT" => "",
    "EXECUTABLE_EXTS" => "",
    "DLEXT" => dlext,
    "SOEXT" => soext,
    "LIBEXT" => "a",
    "OBJEXT" => "o",

    # Install layout, prefix-relative. `rubylibprefix` is the load-bearing one:
    # `Gem.default_dir` is it plus `gems/<ruby_version>`, and
    # `Gem.default_specifications_dir` hangs off that in turn.
    "prefix" => prefix,
    "exec_prefix" => prefix,
    "bindir" => zr_bindir,
    "libdir" => "#{prefix}/lib",
    "rubylibprefix" => "#{prefix}/lib/ruby",
    "rubylibdir" => "#{prefix}/lib/ruby/#{ruby_version}",
    "archdir" => "#{prefix}/lib/ruby/#{ruby_version}/#{arch}",
    "rubyarchdir" => "#{prefix}/lib/ruby/#{ruby_version}/#{arch}",
    "sitedir" => "#{prefix}/lib/ruby/site_ruby",
    "sitelibdir" => "#{prefix}/lib/ruby/site_ruby/#{ruby_version}",
    "sitearchdir" => "#{prefix}/lib/ruby/site_ruby/#{ruby_version}/#{arch}",
    "vendordir" => "#{prefix}/lib/ruby/vendor_ruby",
    "vendorlibdir" => "#{prefix}/lib/ruby/vendor_ruby/#{ruby_version}",
    "vendorarchdir" => "#{prefix}/lib/ruby/vendor_ruby/#{ruby_version}/#{arch}",
    "sysconfdir" => "#{prefix}/etc",
    "mandir" => "#{prefix}/share/man",
    "datadir" => "#{prefix}/share",
    "localstatedir" => "/var",

    # Feature flags rubygems consults.
    # zr has no libruby: a program is one static binary.
    "ENABLE_SHARED" => "no",
    "host_os_version" => os.sub(/\A\D*/, ""),
    "CC" => ENV["CC"] || "cc",
    "CXX" => ENV["CXX"] || "c++",
    "LD" => ENV["LD"] || "ld",
    "AR" => "ar",
    "LDSHARED" => ldshared,
    # A C extension is a BUNDLE that resolves `rb_*` against the host binary
    # at load, so its own link must leave them undefined. Without this every
    # extension fails to link with "Undefined symbols ... _rb_define_method",
    # which looks like a missing implementation but is not one.
    # CRuby's own `DLDFLAGS` contains the same flag.
    "DLDFLAGS" => undefined_flag,
    "configure_args" => "",

    # --- The keys `mkmf` reads. -------------------------------------------
    #
    # zr has no build tree, so the header directories name the cache a C
    # extension build would fill.
    "topdir" => hdrdir,
    "hdrdir" => hdrdir,
    "rubyhdrdir" => hdrdir,
    "rubyarchhdrdir" => archhdrdir,
    "srcdir" => ".",
    "build_os" => host_os,
    "GCC" => "yes",
    "CC_WRAPPER" => "",
    "CCDLFLAGS" => "-fPIC",
    "CSRCFLAG" => "",
    "COUTFLAG" => "-o ",
    "OUTFLAG" => "-o ",
    "CPPOUTFILE" => "-o conftest.i",
    "PATH_SEPARATOR" => ":",
    "NULLCMD" => ":",
    "MKMF_VERBOSE" => "0",
    "DEFS" => "",
    "DLDLIBS" => "",
    "EXTDLDFLAGS" => "",
    "LIBRUBY" => "",
    "LIBRUBY_A" => "",
    "LIBRUBYARG" => "",
    "LIBRUBYARG_SHARED" => "",
    "LIBRUBYARG_STATIC" => "",
    "LIBS" => "-lm -lpthread",
    "SOLIBS" => "",
    "cflags" => "$(optflags) $(debugflags) $(warnflags) $(unwindflags)",
    "cxxflags" => "$(optflags) $(debugflags) $(warnflags) $(unwindflags)",
    "cppflags" => "",
    "optflags" => "-O2",
    "debugflags" => "-g",
    "warnflags" => "-Wall -Wextra -Wno-unused-parameter -Wno-missing-field-initializers",
    # A raise unwinds through the extension's own frames, so its objects
    # must contain unwind tables (docs/EXTENSIONS.md).
    "unwindflags" => "-fexceptions -fasynchronous-unwind-tables",
    "CFLAGS" => "$(cflags) -fPIC",
    "CXXFLAGS" => "$(cxxflags) -fPIC",
    "CPPFLAGS" => "$(DEFS) $(cppflags)",
    "LDFLAGS" => "",
    "ARCH_FLAG" => "",
    "STRIP" => "strip -A -n",
    "TRY_LINK" => "",
    "COMMON_HEADERS" => "",
    "COMMON_MACROS" => "",
    "COMMON_LIBS" => "",
    "RUBY_PROGRAM_VERSION" => RUBY_VERSION.dup,
    "UNICODE_VERSION" => "17.0.0",
    "UNICODE_EMOJI_VERSION" => "17.0",
    "UNIVERSAL_ARCHNAMES" => "",
    "universal" => "",

    # --- The rest of CRuby's keys, as its configure gives them. -----------
    "RUBY_API_VERSION" => api.dup,
    "RUBY_VERSION_NAME" => "ruby-#{ruby_version}",
    "RUBY_LIB_VERSION" => "",
    "RUBY_LIB_VERSION_STYLE" => "3\t/* full */",
    "RUBY_EXEC_PREFIX" => "",
    "RUBY_SEARCH_PATH" => "",
    "RUBY_DEVEL" => "",
    "RUBYW_BASE_NAME" => "rubyw",
    "RUBYW_INSTALL_NAME" => "",
    "rubyw_install_name" => "",
    "RI_BASE_NAME" => "ri",
    "PACKAGE" => "ruby",
    "PACKAGE_BUGREPORT" => "",
    "PACKAGE_NAME" => "",
    "PACKAGE_STRING" => "",
    "PACKAGE_TARNAME" => "",
    "PACKAGE_URL" => "",
    "PACKAGE_VERSION" => "",
    "build" => triple,
    "build_alias" => "",
    "build_cpu" => host_cpu,
    "build_vendor" => vendor,
    "config_target" => triple,
    "target_alias" => "",
    "CROSS_COMPILING" => "no",
    "THREAD_MODEL" => "pthread",
    "COROUTINE_TYPE" => host_cpu == "x86_64" ? "amd64" : "arm64",
    "SYMBOL_PREFIX" => darwin ? "_" : "",
    "LIBPATHENV" => darwin ? "DYLD_LIBRARY_PATH" : "LD_LIBRARY_PATH",
    "PRELOADENV" => darwin ? "DYLD_INSERT_LIBRARIES" : "LD_PRELOAD",
    "LIBPATHFLAG" => " -L%s",
    "RPATHFLAG" => darwin ? "" : " -Wl,-rpath,%1$-s",
    "MAINLIBS" => darwin ? "-ldl -lobjc -lpthread " : "-lz -lrt -lrt -ldl -lcrypt -lm -lpthread ",
    "LIBRUBY_SO" => "lib$(RUBY_SO_NAME).#{soext}.$(RUBY_PROGRAM_VERSION)",
    "LIBRUBY_SONAME" => "lib$(RUBY_SO_NAME).#{soext}.$(RUBY_API_VERSION)",
    "LIBRUBY_ALIASES" => "lib$(RUBY_SO_NAME).#{soext}",
    "LIBRUBY_RELATIVE" => "no",
    "ruby_pc" => "ruby-#{api}.pc",
    "modular_gc_dir" => "",
    "ENCSTATIC" => "",
    "EXTSTATIC" => "",
    "STATIC" => "",
    "EXTOUT" => ".ext",
    "EXTLDFLAGS" => "",
    "ADDITIONAL_DLDFLAGS" => "",
    "DLDSHARED" => darwin ? "cc -dynamiclib" : "cc -shared",
    "LDSHAREDXX" => darwin ? "c++ -dynamic -bundle" : "c++ -shared",
    "GNU_LD" => darwin ? "no" : "yes",
    "CPP" => "$(CC) -E",
    "CC_VERSION" => "$(CC) --version",
    "CC_VERSION_MESSAGE" => "",
    "AS" => "as",
    "ASMEXT" => "S",
    "ARFLAGS" => "rcu ",
    "RANLIB" => "ranlib",
    "NM" => "nm",
    "OBJCOPY" => ":",
    "OBJDUMP" => "objdump",
    "dsymutil" => darwin ? "dsymutil" : "",
    "codesign" => darwin ? "codesign" : "",
    "POSTLINK" => "",
    "LINK_SO" => "",
    "cleanlibs" => "",
    "hardenflags" => "-fstack-protector-strong -U_FORTIFY_SOURCE -D_FORTIFY_SOURCE=2",
    "incflags" => "",
    "strict_warnflags" => "",
    "WERRORFLAG" => "-Werror",
    "try_header" => "",
    "ALLOCA" => "",
    "ARCHFILE" => "",
    "DLNOBJ" => "dln.o",
    "DLLWRAP" => "",
    "WINDRES" => "",
    "USE_LLVM_WINDRES" => "",
    "EXPORT_PREFIX" => "",
    "PLATFORM_DIR" => "",
    "UNIVERSAL_INTS" => "",
    "BUILTIN_TRANSSRCS" => " enc/trans/newline.c",
    "ENABLE_DEBUG_ENV" => "",
    "TEST_RUNNABLE" => "yes",
    "INSTALL_STATIC_LIBRARY" => "yes",
    "SDKROOT" => "",
    "PKG_CONFIG_PATH" => "#{prefix}/lib/pkgconfig",
    "PREP" => "miniruby",
    "setup" => "Setup",
    "CONFIGURE" => "configure",
    "MANTYPE" => "doc",
    "libdirname" => "libdir",
    # zr compiles ahead of time: no YJIT, no ZJIT, no Rust.
    "YJIT_SUPPORT" => "no",
    "YJIT_LIBS" => "",
    "YJIT_OBJ" => "",
    "ZJIT_SUPPORT" => "no",
    "ZJIT_LIBS" => "",
    "ZJIT_OBJ" => "",
    "ZJIT_TEST_FEATURES" => "",
    "JIT_OBJ" => "",
    "JIT_CARGO_SUPPORT" => "no",
    "JIT_RUST_FLAGS" => "",
    "CARGO" => "",
    "CARGO_BUILD_ARGS" => "",
    "RUSTC" => "",
    "RUST_LIB" => "",
    "RLIB_DIR" => "",
    "WASMOPT" => "",
    "wasmoptflags" => "",
    "DOT" => "",
    "DOXYGEN" => "",
    "GIT" => "git",
    "HAVE_GIT" => "yes",
    # The shell tools a Makefile of mkmf's calls.
    "SHELL" => "/bin/sh",
    "CHDIR" => "cd -P",
    "CP" => "cp",
    "RM" => "rm -f",
    "RMALL" => "rm -fr",
    "RMDIR" => "rmdir",
    "RMDIRS" => "rmdir -p",
    "MAKEDIRS" => "mkdir -p",
    "MKDIR_P" => "mkdir -p",
    "LN_S" => "ln -s",
    "INSTALL" => "/usr/bin/install -c",
    "INSTALL_DATA" => "$(INSTALL) -m 644",
    "INSTALL_PROGRAM" => "$(INSTALL)",
    "INSTALL_SCRIPT" => "$(INSTALL)",
    "GREP" => "/usr/bin/grep",
    "EGREP" => "/usr/bin/grep -E",
    "SET_MAKE" => "",
    "MAKEFILES" => "Makefile GNUmakefile",
    "ECHO_C" => "\\\\c",
    "ECHO_N" => "",
    "ECHO_T" => "",
    "exec" => "exec",
    # The rest of the install layout.
    "datarootdir" => "#{prefix}/share",
    "docdir" => "#{prefix}/share/doc/ruby",
    "htmldir" => "#{prefix}/share/doc/ruby",
    "dvidir" => "#{prefix}/share/doc/ruby",
    "pdfdir" => "#{prefix}/share/doc/ruby",
    "psdir" => "#{prefix}/share/doc/ruby",
    "infodir" => "#{prefix}/share/info",
    "localedir" => "#{prefix}/share/locale",
    "ridir" => "#{prefix}/share/ri",
    "includedir" => "#{prefix}/include",
    "oldincludedir" => "/usr/include",
    "archincludedir" => "#{prefix}/include/#{arch}",
    "sitearchincludedir" => "#{prefix}/include/#{arch}",
    "archlibdir" => "#{prefix}/lib/#{arch}",
    "sitearchlibdir" => "#{prefix}/lib/#{arch}",
    "libexecdir" => "#{prefix}/libexec",
    "sbindir" => "#{prefix}/sbin",
    "sharedstatedir" => "#{prefix}/com",
    "runstatedir" => "#{prefix}/var/run",
    "rubyarchprefix" => "#{prefix}/lib/ruby/#{arch}",
    "rubysitearchprefix" => "#{prefix}/lib/ruby/#{arch}",
    "sitehdrdir" => "#{hdrdir}/site_ruby",
    "sitearchhdrdir" => "#{hdrdir}/site_ruby/#{arch}",
    "vendorhdrdir" => "#{hdrdir}/vendor_ruby",
    "vendorarchhdrdir" => "#{hdrdir}/vendor_ruby/#{arch}",
  }

  # `MAKEFILE_CONFIG`'s values keep their `$(var)` references: mkmf writes
  # them into the Makefile verbatim, and `make` is what expands them. `CONFIG`
  # is the same table with every reference already resolved, which is what
  # `expand` below does.
  MAKEFILE_CONFIG = CONFIG.dup
  # The prefix of an installed layout, as ruby gives it, or nil when the
  # layout is not there.
  TOPDIR = File.directory?(CONFIG["rubylibdir"]) ? prefix : nil

  # `RbConfig.ruby` -- the full path to the running interpreter, which is
  # zr: the `zr` that ran the program (`ZR_RUBY`, which `zr run` and `zr
  # app.rb` set), else the one in `ZR_BINDIR` or `ZR_PREFIX`, else the
  # first `zr` on PATH, else `~/.zr/bin/zr`. So `system(RbConfig.ruby,
  # "-e", ...)` runs zr, as it runs ruby in a ruby program.
  def self.ruby
    given = Primitive.zr_hidden_get(ENV, :__zr_ruby__)
    return given unless given.nil? || given.empty?

    name = CONFIG["ruby_install_name"] + CONFIG["EXEEXT"]
    unless ENV["ZR_BINDIR"] || ENV["ZR_PREFIX"]
      found = ENV["PATH"].to_s.split(File::PATH_SEPARATOR).map { |dir| File.join(dir, name) }
                         .find { |path| File.file?(path) && File.executable?(path) }
      return found if found
    end
    File.join(CONFIG["bindir"], name)
  end

  # `RbConfig.fire_update!` -- upstream's, transcribed: sets `key` in
  # MAKEFILE_CONFIG, then expands again each entry of CONFIG that refers
  # to it, directly or through another entry. It returns those keys.
  def self.fire_update!(key, val, mkconf = MAKEFILE_CONFIG, conf = CONFIG)
    return if mkconf[key] == val

    mkconf[key] = val
    keys = [key]
    deps = []
    begin
      re = Regexp.new("\\$\\((?:%1$s)\\)|\\$\\{(?:%1$s)\\}" % keys.join("|"))
      deps |= keys
      keys.clear
      mkconf.each { |k, v| keys << k if re =~ v }
    end until keys.empty? # rubocop:disable Lint/Loop -- rbconfig.rb's own loop, as ruby writes it
    deps.each { |k| conf[k] = mkconf[k].dup }
    deps.each { |k| expand(conf[k]) }
    deps
  end

  # `RbConfig.expand` -- upstream's implementation, transcribed.
  #
  # Two details are load-bearing and neither is obvious. It MUTATES `val` in
  # place (`val.replace`) and callers depend on that: mkmf writes
  # `RbConfig.expand(srcdir = srcprefix.dup)` and then reads `srcdir`,
  # discarding the return value. And it expands the config entry it reaches
  # THROUGH, memoizing the result, so `$(CFLAGS)` resolves the whole chain in
  # one pass and a cycle raises instead of spinning.
  #
  # An earlier version here returned a new String and left `val` alone. Every
  # generated Makefile came out with an empty `SRCS`, because mkmf's `srcdir`
  # stayed the literal `$(srcdir)` and globbed nothing.
  def self.expand(val, config = CONFIG)
    return val unless val.is_a?(String)

    newval = val.gsub(/\$\$|\$\(([^()]+)\)|\$\{([^{}]+)\}/) do
      var = Regexp.last_match(0)
      name = Regexp.last_match(1) || Regexp.last_match(2)
      if name.nil?
        "$"
      else
        # `$(var:pat=sub)` -- a make-style suffix substitution.
        name = name[/\A[^:]+(?=(?::(.*?)=(.*))?\z)/]
        pat = Regexp.last_match(1)
        sub = Regexp.last_match(2)
        key = config[name]
        if key
          config[name] = false
          config[name] = key = expand(key, config)
          key = key.gsub(/#{Regexp.quote(pat)}(?=\s|\z)/) { sub } if pat
          key
        elsif key == false
          raise "recursive expansion of #{var}"
        else
          var
        end
      end
    end
    val.replace(newval) unless newval == val
    val
  end
end

# Resolve every `$(var)` in `CONFIG` itself. `MAKEFILE_CONFIG` keeps them,
# because that is the table mkmf writes into the Makefile for `make` to
# expand.
#
# Neither is FROZEN, and real rbconfig does not freeze them either. mkmf
# writes into both -- `init_mkmf` rewrites `warnflags` and `CC_WRAPPER` --
# so a frozen table is a `FrozenError` before any extension is configured.
RbConfig::CONFIG.each_key do |k|
  RbConfig::CONFIG[k] = RbConfig.expand(RbConfig::CONFIG[k], RbConfig::CONFIG)
end
