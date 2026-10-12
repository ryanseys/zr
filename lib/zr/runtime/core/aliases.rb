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
  [NilClass, :|, :^], [TrueClass, :to_s, :inspect], [FalseClass, :|, :^], [FalseClass, :to_s, :inspect]
].each { |klass, original, name| Primitive.zr_method_alias_of(klass, name, original) }

[[Array, :<<], [Integer, :to_int], [Kernel, :iterator?], [Kernel, :yield_self]].each do |klass, name|
  Primitive.zr_method_alone(klass, name)
end
