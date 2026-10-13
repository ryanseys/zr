# The first Ractor.new gives Object a require of its own, which aliases
# the old one as __ractor_original_require. In a ractor that is not the
# main one it calls Ractor._require, and the main ractor then calls
# `require` on nil with the path, so a require that the program
# redefines in Kernel runs there.
require "tmpdir"
Warning[:experimental] = false

p Object.private_method_defined?(:__ractor_original_require)
p Object.private_instance_methods(false).include?(:require)
p Ractor.instance_variables

Dir.mktmpdir do |dir|
  first = File.join(dir, "rq_first.rb")
  second = File.join(dir, "rq_second.rb")
  File.write(first, "RQ_FIRST = :first\n")
  File.write(second, "RQ_SECOND = :second\n")

  class << Ractor
    alias __orig_ractor_require _require
    def _require(feature)
      (Ractor.current[:required] ||= []) << [inspect, __method__, File.basename(feature.to_s)]
      __orig_ractor_require(feature)
    end
  end

  Ractor.new { nil }.join
  p Object.private_method_defined?(:__ractor_original_require)
  p Object.private_instance_methods(false).include?(:require)
  p Object.instance_method(:require).owner
  p Ractor.instance_variables

  # The ractor's own require goes through Ractor._require, which the
  # program redefined, so the ractor records it.
  p(Ractor.new(first) do |path|
    [require(path), RQ_FIRST, Ractor.current[:required]]
  end.value)
  p Ractor.current[:required]

  module Kernel
    alias rq_original_require require
    def require(feature)
      (Ractor.current[:required] ||= []) << [inspect, __method__, File.basename(feature.to_s)]
      rq_original_require(feature)
    end
  end

  # The main ractor runs Kernel's redefined require with nil as self.
  p(Ractor.new(second) do |path|
    [require(path), RQ_SECOND, Ractor.current[:required]]
  end.value)
  p Ractor.current[:required]

  # In the main ractor, Object's require passes the call to Kernel's.
  Ractor.current[:required] = nil
  p require(second)
  p Ractor.current[:required]

  # Kernel.require in a ractor also runs on the main ractor.
  Ractor.current[:required] = nil
  p Ractor.new(first) { |path| Kernel.require(path) }.value
  p Ractor.current[:required]

  # A require of a missing file raises LoadError in the ractor.
  p(Ractor.new(dir) do |path|
    require File.join(path, "rq_missing")
  rescue LoadError => e
    [e.class, File.basename(e.path)]
  end.value)
end
