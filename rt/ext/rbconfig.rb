# frozen_string_literal: false
#
# NOT frozen-literal, and not by omission. Real rbconfig's values are mutable
# strings -- `RbConfig::CONFIG["cflags"].frozen?` is false on the oracle --
# and both `RbConfig.expand` and mkmf's `init_mkmf` write THROUGH them with
# `String#replace`. A frozen literal here is a `FrozenError` before any
# extension is configured.
#
# ze0's own `rbconfig`. Ruby generates this file at build time from its
# build configuration; ze0 has no such build, so the facts come from the
# running program instead. It carries the keys rubygems and bundler read:
# version, platform, and the install layout.
#
module RbConfig
  ruby_version = "4.0.0"

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

  # The install layout is the ruby's that compiled the program, so
  # rubygems finds the gems that ruby has installed, as ruby itself would.
  # The environment names another; with neither, it is a directory under
  # the home directory that ze0 owns, which rubygems may create.
  compiled_by = Primitive.zr_load_names(5).lines(chomp: true).to_h { |line| line.split("=", 2) }
  prefix = ENV["ZE0_PREFIX"] || compiled_by["prefix"]&.dup || File.join(ENV["HOME"] || "/tmp", ".ze0")

  # Where MRI's headers live for a C extension build. ze0 builds no C
  # extension yet, so these name the cache a later one would fill.
  hdrdir = ENV["ZE0_CEXT_HDRDIR"] || "#{prefix}/include/ruby-#{ruby_version}"
  archhdrdir = ENV["ZE0_CEXT_ARCHHDRDIR"] || "#{hdrdir}/#{RUBY_PLATFORM}"

  # `RbConfig.ruby` is `bindir` plus `ruby_install_name`, and rubygems
  # spawns exactly that string. The interpreter is ze0.
  ze0_bindir = ENV["ZE0_BINDIR"] || "#{prefix}/bin"
  ze0_ruby_name = ENV["ZE0_RUBY_INSTALL_NAME"] || "ze0"

  CONFIG = {
    "MAJOR" => "4",
    "MINOR" => "0",
    "TEENY" => "0",
    "PATCHLEVEL" => "5",
    "ruby_version" => ruby_version,
    "RUBY_SO_NAME" => "ruby.4.0",
    "ruby_install_name" => ze0_ruby_name,
    "RUBY_INSTALL_NAME" => ze0_ruby_name,
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
    "bindir" => ze0_bindir,
    "libdir" => "#{prefix}/lib",
    "rubylibprefix" => "#{prefix}/lib/ruby",
    "rubylibdir" => "#{prefix}/lib/ruby/#{ruby_version}",
    "archdir" => "#{prefix}/lib/ruby/#{ruby_version}/#{arch}",
    "rubyarchdir" => "#{prefix}/lib/ruby/#{ruby_version}/#{arch}",
    "topdir" => "#{prefix}/lib/ruby/#{ruby_version}/#{arch}",
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
    "ENABLE_SHARED" => compiled_by.fetch("ENABLE_SHARED", "yes").dup,
    "host_os_version" => os.sub(/\A\D*/, ""),
    "CC" => ENV["CC"] || "cc",
    "CXX" => ENV["CXX"] || "c++",
    "LD" => ENV["LD"] || "ld",
    "AR" => "ar",
    "LDSHARED" => ldshared,
    # A C extension is a BUNDLE that resolves `rb_*` against the host binary
    # at load, so its own link must leave them undefined. Without this every
    # extension fails to link with "Undefined symbols ... _rb_define_method",
    # which reads like a missing implementation and is not one.
    # The oracle's own `DLDFLAGS` carries the same flag.
    "DLDFLAGS" => undefined_flag,
    "configure_args" => "",

    # --- The keys `mkmf` reads. -------------------------------------------
    #
    # ze0 has no build tree, so the header directories name the cache a C
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
    # must carry unwind tables (docs/EXTENSIONS.md).
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
    "RUBY_PROGRAM_VERSION" => ruby_version,
    "UNIVERSAL_ARCHNAMES" => "",
    "universal" => "",
  }

  # `MAKEFILE_CONFIG`'s values keep their `$(var)` references: mkmf writes
  # them into the Makefile verbatim, and `make` is what expands them. `CONFIG`
  # is the same table with every reference already resolved, which is what
  # `expand` below does.
  MAKEFILE_CONFIG = CONFIG.dup
  TOPDIR = CONFIG["topdir"]

  # `RbConfig.ruby` -- the full path to the running interpreter.
  def self.ruby
    File.join(CONFIG["bindir"], CONFIG["ruby_install_name"] + CONFIG["EXEEXT"])
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
