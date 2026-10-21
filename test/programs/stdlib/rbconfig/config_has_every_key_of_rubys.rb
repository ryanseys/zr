# RbConfig::CONFIG has the keys that ruby's configure gives, which mkmf
# and gems read; the values that do not name a place are ruby's.
require "rbconfig"
keys = %w[
  RUBY_API_VERSION RUBY_VERSION_NAME THREAD_MODEL LIBPATHENV PRELOADENV SYMBOL_PREFIX modular_gc_dir
  MAINLIBS LIBRUBY_SO LIBRUBY_SONAME LIBRUBY_ALIASES includedir datarootdir docdir libexecdir sbindir
  sitehdrdir vendorhdrdir sitearchhdrdir vendorarchhdrdir archincludedir CROSS_COMPILING PACKAGE
  SHELL CP RM MKDIR_P INSTALL INSTALL_DATA CPP NM RANLIB build config_target GNU_LD COROUTINE_TYPE
]
p keys.reject { |key| RbConfig::CONFIG.key?(key) }
p keys.reject { |key| RbConfig::MAKEFILE_CONFIG.key?(key) }
%w[THREAD_MODEL modular_gc_dir CROSS_COMPILING PACKAGE SHELL RM].each { |key| p [key, RbConfig::CONFIG[key]] }
# The loader's names and the linker's kind follow the OS, and the
# coroutine the CPU.
os = { "darwin" => %w[DYLD_LIBRARY_PATH DYLD_INSERT_LIBRARIES _ no], "linux" => %w[LD_LIBRARY_PATH LD_PRELOAD] + ["", "yes"] }
p RbConfig::CONFIG.values_at("LIBPATHENV", "PRELOADENV", "SYMBOL_PREFIX", "GNU_LD") == os[RbConfig::CONFIG["host_os"][/darwin|linux/]]
p RbConfig::CONFIG["COROUTINE_TYPE"] == { "x86_64" => "amd64", "aarch64" => "arm64", "arm64" => "arm64" }[RbConfig::CONFIG["host_cpu"]]
# The names that carry the version follow it.
api = RbConfig::CONFIG["RUBY_API_VERSION"]
p api == RUBY_VERSION[/\A\d+\.\d+/]
p RbConfig::CONFIG["RUBY_VERSION_NAME"] == "ruby-#{RbConfig::CONFIG["ruby_version"]}"
p RbConfig::CONFIG["ruby_pc"] == "ruby-#{api}.pc"
p RbConfig::CONFIG["RUBY_SO_NAME"] == "ruby.#{api}"
p RbConfig::CONFIG.values_at("includedir", "docdir", "sitehdrdir").all? { |v| v.start_with?("/") }
# A static ruby's library name ends with the whole version, and a shared
# one's with the API version only; both start with the same name.
p RbConfig::CONFIG["LIBRUBY_SO"].start_with?("lib#{RbConfig::CONFIG["RUBY_SO_NAME"]}.")
p RbConfig::CONFIG["INSTALL_DATA"].end_with?("-m 644")
# The build host chooses its mkdir (a GNU one is gmkdir).
p RbConfig::CONFIG["MKDIR_P"].end_with?("mkdir -p")
