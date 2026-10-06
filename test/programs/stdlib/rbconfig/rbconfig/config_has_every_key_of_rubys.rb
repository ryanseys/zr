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
%w[RUBY_API_VERSION RUBY_VERSION_NAME THREAD_MODEL LIBPATHENV PRELOADENV SYMBOL_PREFIX modular_gc_dir
   CROSS_COMPILING PACKAGE SHELL RM MKDIR_P GNU_LD COROUTINE_TYPE ruby_pc].each { |key| p [key, RbConfig::CONFIG[key]] }
p RbConfig::CONFIG.values_at("includedir", "docdir", "sitehdrdir").all? { |v| v.start_with?("/") }
p RbConfig::CONFIG["LIBRUBY_SO"].end_with?(RbConfig::CONFIG["RUBY_PROGRAM_VERSION"])
p RbConfig::CONFIG["INSTALL_DATA"].end_with?("-m 644")
