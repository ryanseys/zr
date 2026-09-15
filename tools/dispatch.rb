# frozen_string_literal: true

# Writes the programs that show which of its own methods a core class
# calls on the way to answering another: the calls a subclass sees.
#
#   ruby tools/dispatch.rb            # writes every program below
#   ruby tools/record.rb <each path>  # then ruby records what it calls
#
# CRuby's C calls a method by dispatch only where it means to -- Hash#each
# for Enumerable, initialize_copy for dup -- and reaches the rest of its
# own class through C functions no subclass can replace. ze0's core is
# written in Ruby, so a call to `self[k]` in Hash#store is a dispatch, and
# a subclass whose `[]=` calls `store` recurses forever. Each program wraps
# every method the class defines in a subclass that logs a call made from
# inside another, then calls each method once. The recording is exactly the
# set of calls CRuby makes; ze0 answers with the same set or it diverges.
#
# The call made for each method is found here, by trying argument lists on
# the real class until one answers without raising,
# so the programs need no table of arguments written by hand.

require "timeout"

ROOT = File.expand_path("..", __dir__)

# Argument lists to try, in order. A block is tried with each before none.
TRIES = [[], [1], [0, 1], ["l"], [:a], [[1, 2]], [{ a: 1 }], %w[l L], [1, 2, 3], [/l/], [1..2], [2, [3]],
         [:a, 1]].freeze

# Methods whose first answering call would never end or leave the process.
SKIP = %i[cycle freeze display].freeze

CLASSES = {
  "core/hash" => ["Hash", "Probe.new.tap { |h| h[:a] = 1; h[:b] = 2 }"],
  "core/array" => ["Array", "Probe.new([3, 1, 2])"],
  "core/string" => ["String", 'Probe.new(+"hello world")'],
  "core/range" => ["Range", "Probe.new(1, 5)"],
  "core/struct" => ["Struct", "Probe.new(1, 2)"],
  "stdlib/set" => ["Set", "Probe.new([1, 2, 3])"]
}.freeze

NAME = "a_subclass_sees_only_the_calls_ruby_makes.rb"

def base_of(name) = Object.const_get(name)

# The subclass, as source: Struct's is one of its own members.
def probe_class(name)
  name == "Struct" ? "class Probe < Struct.new(:a, :b)" : "class Probe < #{name}"
end

def fresh(name, make)
  eval("#{probe_class(name)}; end; #{make}", binding, __FILE__, __LINE__) # rubocop:disable Security/Eval
ensure
  Object.send(:remove_const, :Probe) if Object.const_defined?(:Probe, false)
end

# The methods a subclass can replace and CRuby's C might call: the
# class's own, public and private, and Enumerable's where it is mixed in.
def wrapped(name)
  base = base_of(name)
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
      warn "#{name}##{m} #{args.inspect} #{block}" if ENV["DISPATCH_TRACE"]
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
    # dispatch only where it means to, and ze0's core, written in Ruby, has
    # to call no more and no fewer. Written by tools/dispatch.rb.

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

CLASSES.each do |dir, (name, make)|
  path = File.join(ROOT, "test", dir, NAME)
  File.write(path, program(name, make))
  puts "wrote #{path.delete_prefix("#{ROOT}/")}"
end
