# frozen_string_literal: true

# The programs that show which of its own methods a core class calls on
# the way to answering another: the calls a subclass sees.
#
#   rake gen:dispatch            # every program below
#   rake 'gen:dispatch[Hash]'    # one of them
#
# Each program is already an example in the spec file named beside it,
# so the task prints rather than writes: read what it prints against the
# heredoc that example carries, and where the two part, ruby says which
# is right. `rake oracle` holds the example's answer to ruby as it holds
# every other.
#
# CRuby's C calls a method by dispatch only where it means to -- Hash#each
# for Enumerable, initialize_copy for dup -- and reaches the rest of its
# own class through C functions no subclass can replace. zr's core is
# written in Ruby, so a call to `self[k]` in Hash#store is a dispatch, and
# a subclass whose `[]=` calls `store` recurses forever. Each program wraps
# every method the class defines in a subclass that logs a call made from
# inside another, then calls each method once. The recording is exactly the
# set of calls CRuby makes; zr answers with the same set or it diverges.
#
# The call made for each method is found here, by trying argument lists on
# the real class until one answers without raising, so the programs need
# no table of arguments written by hand.

require "timeout"
require "zr/flags"

module Dispatch
  # Argument lists to try, in order. A block is tried with each before none.
  TRIES = [[], [1], [0, 1], ["l"], [:a], [[1, 2]], [{ a: 1 }], %w[l L], [1, 2, 3], [/l/], [1..2], [2, [3]],
           [:a, 1]].freeze

  # Methods whose first answering call would never end or leave the process.
  SKIP = %i[cycle freeze display].freeze

  # The class, how a fresh receiver is made, and the spec file holding
  # the example this program is.
  CLASSES = {
    "Hash" => ["Probe.new.tap { |h| h[:a] = 1; h[:b] = 2 }", "test/spec/core/hash/hash_test.rb"],
    "Array" => ["Probe.new([3, 1, 2])", "test/spec/core/array/array_test.rb"],
    "String" => ['Probe.new(+"hello world")', "test/spec/core/string/string_test.rb"],
    "Range" => ["Probe.new(1, 5)", "test/spec/core/range/range_test.rb"],
    "Struct" => ["Probe.new(1, 2)", "test/spec/core/struct/inheritance_test.rb"],
    "Set" => ["Probe.new([1, 2, 3])", "test/spec/stdlib/set/set_test.rb"]
  }.freeze

  EXAMPLE = "subclass sees only the calls ruby makes"

  module_function

  def show(wanted)
    wanted = CLASSES.keys if wanted.empty?
    unknown = wanted - CLASSES.keys
    abort("rake gen:dispatch: no program for #{unknown.join(", ")}") unless unknown.empty?

    wanted.each do |name|
      make, spec = CLASSES.fetch(name)
      puts "# #{spec}: it #{EXAMPLE.inspect}"
      puts program(name, make)
      puts
    end
  end

  # The subclass, as source: Struct's is one of its own members.
  def probe_class(name)
    name == "Struct" ? "class Probe < Struct.new(:a, :b)" : "class Probe < #{name}"
  end

  # A receiver of a fresh subclass. The eval runs against `Object`, so
  # the subclass is the top-level `Probe` the generated program names.
  def fresh(name, make)
    Object.class_eval("#{probe_class(name)}; end; #{make}", __FILE__, __LINE__)
  ensure
    Object.send(:remove_const, :Probe) if Object.const_defined?(:Probe, false)
  end

  # The methods a subclass can replace and CRuby's C might call: the
  # class's own, public and private, and Enumerable's where it is mixed in.
  def wrapped(name)
    base = Object.const_get(name)
    names = base.public_instance_methods(false) + base.private_instance_methods(false)
    names += Enumerable.public_instance_methods(false) if base.include?(Enumerable)
    names += Comparable.public_instance_methods(false) if base.include?(Comparable)
    (names.uniq - %i[initialize method_missing respond_to_missing?]).sort
  end

  # The call to make for `m`: its source, or nil when nothing answers.
  def call_for(name, make, m)
    return nil if SKIP.include?(m)

    TRIES.each do |args|
      [true, false].each do |block|
        receiver = fresh(name, make)
        warn "#{name}##{m} #{args.inspect} #{block}" if Zr.flag?("ZR_DISPATCH_TRACE")
        begin
          Timeout.timeout(1) do
            block ? receiver.__send__(m, *args) { |*x| x.first } : receiver.__send__(m, *args)
          end
        rescue StandardError, NotImplementedError
          next
        end
        text = args.map(&:inspect).join(", ")
        call = if m.match?(/\A[a-z_]\w*[?!]?\z/)
                 "r.#{m}(#{text})"
               else
                 "r.__send__(#{[m.inspect, text].reject(&:empty?).join(", ")})"
               end
        return block ? "#{call} { |*x| x.first }" : call
      end
    end
    nil
  end

  def program(name, make)
    calls = wrapped(name).filter_map { |m| (c = call_for(name, make, m)) && [m, c] }
    <<~RUBY
      # Which of #{name}'s own methods its methods call on a subclass: every
      # method #{name} defines is wrapped to log a call made from inside another,
      # and each is then called once on a fresh receiver. CRuby calls one by
      # dispatch only where it means to, and zr's core, written in Ruby, has
      # to call no more and no fewer. Written by `rake gen:dispatch`.

      #{probe_class(name)}
        CALLING = []
        LOG = []
        #{wrapped(name).inspect}.each do |m|
          define_method(m) do |*args, &blk|
            LOG << "\#{CALLING.last}->\#{m}" unless CALLING.empty?
            CALLING << m
            begin
              super(*args, &blk)
            ensure
              CALLING.pop
            end
          end
          ruby2_keywords(m)
        end
      end

      def call(name)
        r = #{make}
        Probe::LOG.clear
        begin
          yield r
        rescue StandardError => e
          Probe::LOG << "raised \#{e.class}"
        end
        puts "\#{name}: \#{Probe::LOG.join(" ")}" unless Probe::LOG.empty?
      end

      #{calls.map { |m, c| "call(#{m.to_s.inspect}) { |r| #{c} }" }.join("\n")}
    RUBY
  end
end

namespace :gen do
  desc "Print the programs that show which of its own methods a core class calls"
  task(:dispatch, [:classes]) { |_, args| Dispatch.show(args[:classes].to_s.split) }
end
