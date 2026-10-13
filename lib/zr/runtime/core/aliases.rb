# frozen_string_literal: true

# Method#== and #hash compare method definitions (rb_method_entry_eq): an
# alias is its original, and two methods that CRuby defines with one C
# function are one. zr writes some of these apart, and shares code
# between some that CRuby keeps apart, so this table says which core
# methods are one and which are alone (zr_method_alias_of,
# zr_method_alone). It runs last, when every core method is defined.

[
  [Array, :[], :slice], [Array, :push, :append], [Array, :map, :collect], [Array, :map!, :collect!],
  [Array, :select!, :filter!], [Array, :index, :find_index], [Array, :replace, :initialize_copy],
  [Hash, :[]=, :store], [Hash, :replace, :initialize_copy],
  [String, :replace, :initialize_copy], [Symbol, :to_sym, :intern],
  [Integer, :%, :modulo], [Integer, :succ, :next], [Float, :quo, :fdiv], [Numeric, :abs, :magnitude],
  [IO, :fsync, :fdatasync], [IO, :path, :to_path], [Dir, :tell, :pos],
  [Enumerable, :map, :collect], [Enumerable, :flat_map, :collect_concat], [Enumerable, :to_a, :entries],
  [Enumerable, :inject, :reduce], [Enumerator, :each_with_object, :with_object], [Kernel, :format, :sprintf],
  [Module, :const_added, :extended], [Module, :const_added, :included], [Module, :const_added, :method_added],
  [Module, :const_added, :method_removed], [Module, :const_added, :method_undefined], [Module, :const_added, :prepended],
  [BasicObject, :singleton_method_added, :singleton_method_removed],
  [BasicObject, :singleton_method_added, :singleton_method_undefined],
  [Enumerator::Lazy, :map, :collect], [Enumerator::Lazy, :flat_map, :collect_concat],
  [Enumerator::Lazy, :select, :filter], [Enumerator::Lazy, :select, :find_all],
  [Enumerator::Lazy, :chunk, :chunk_while], [Enumerator::Lazy, :chunk, :slice_after],
  [Enumerator::Lazy, :chunk, :slice_before], [Enumerator::Lazy, :chunk, :slice_when],
  [NilClass, :|, :^], [TrueClass, :to_s, :inspect], [FalseClass, :|, :^], [FalseClass, :to_s, :inspect],
  [Regexp.singleton_class, :escape, :quote], [FileTest.singleton_class, :empty?, :zero?],
  [File.singleton_class, :empty?, :zero?], [Kernel.singleton_class, :format, :sprintf],
  [Process.singleton_class, :wait, :waitpid], [Process.singleton_class, :wait2, :waitpid2]
].each { |klass, original, name| Primitive.zr_method_alias_of(klass, name, original) }

[[Array, :<<], [Integer, :to_int], [Kernel, :iterator?]].each do |klass, name|
  Primitive.zr_method_alone(klass, name)
end

# Kernel#yield_self is == to then, its original in ruby's kernel.rb, and
# Method#hash still tells them apart.
Primitive.zr_method_hash_apart(Kernel, :yield_self)

# The aliases that CRuby makes with rb_define_alias, or writes in its Ruby
# files, are its original method: a backtrace shows the original's name
# (zr_method_label_original). zr's other core aliases are methods that
# CRuby defines apart, and show their own.
[
  [Numeric, :imag], [Numeric, :conj], [Integer, :inspect], [Integer, :magnitude], [IO, :to_i], [Kernel, :yield_self],
  [Marshal.singleton_class, :restore], [Data, :to_s], [Struct, :to_s], [MatchData, :deconstruct], [String, :dedup],
  [Symbol, :id2name], [Encoding, :to_s], [Thread::Queue, :<<], [Thread::Queue, :enq],
  [Pathname, :===], [Pathname, :eql?], [Pathname, :to_path], [Pathname, :/], [Pathname, :delete], [Pathname.singleton_class, :pwd],
  [Time.singleton_class, :gm], [Time.singleton_class, :mktime],
  [Ractor, :<<], [Ractor, :recv], [Ractor, :to_s], [Ractor.singleton_class, :recv], [Ractor::Port, :<<],
  [Set, :intersection], [Set, :difference], [Set, :+], [Set, :union], [Set, :eql?], [Set, :<<], [Set, :map!], [Set, :member?],
  [Set, :===], [Set, :to_s], [Set, :<], [Set, :>], [Set, :length], [Set, :filter!], [Set, :<=], [Set, :>=]
].each { |klass, name| Primitive.zr_method_label_original(klass, name) }

# The methods that zr defines apart from what CRuby makes them an alias
# of: a backtrace shows the original's name (zr_method_label_as).
[[Array, :append, :push], [Array, :prepend, :unshift], [Symbol, :intern, :to_sym], [Float, :magnitude, :abs]].each do |klass, name, original|
  Primitive.zr_method_label_as(klass, name, original)
end
