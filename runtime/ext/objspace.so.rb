# frozen_string_literal: true

# `objspace.so`: the C half of ext/objspace, over the kernel's walk of the
# heap (runtime/kernel/objspace.rb). The Ruby half, objspace.rb, is ruby's own.
# Sizes are this runtime's: a cell is 128 bytes, and what a String, an
# Array or a Hash keeps outside its cell counts with it.
module ObjectSpace
  # What reachable_objects_from returns for a cell that no program can
  # reach: the cell seen from outside, as its address and its type.
  class InternalObjectWrapper
    Primitive.zr_undef_alloc(self)

    def self.of(address, type)
      Primitive.attr! :hidden
      wrapper = Primitive.zr_class_build(self)
      Primitive.zr_hidden_set(wrapper, :__address__, address)
      Primitive.zr_hidden_set(wrapper, :__type__, type)
      wrapper
    end

    def type = Primitive.zr_hidden_get(self, :__type__)
    def internal_object_id = Primitive.zr_hidden_get(self, :__address__)
    def inspect = "#<InternalObject:0x#{internal_object_id.to_s(16).rjust(16, "0")} #{type}>"
  end

  # count_objects_size and dump name a type as CRuby's heap tags it.
  HEAP_TYPES = [
    [String, "STRING"], [Array, "ARRAY"], [Hash, "HASH"], [Class, "CLASS"], [Module, "MODULE"],
    [Float, "FLOAT"], [Regexp, "REGEXP"], [Symbol, "SYMBOL"], [Struct, "STRUCT"], [Integer, "BIGNUM"],
    [IO, "FILE"], [MatchData, "MATCH"], [Complex, "COMPLEX"], [Rational, "RATIONAL"],
    [Proc, "DATA"], [Method, "DATA"], [UnboundMethod, "DATA"], [Thread, "DATA"], [Fiber, "DATA"]
  ].freeze
  # The types in the order of CRuby's tags.
  TYPE_ORDER = %w[OBJECT CLASS MODULE FLOAT STRING REGEXP ARRAY HASH STRUCT BIGNUM FILE DATA MATCH COMPLEX RATIONAL SYMBOL].freeze
  private_constant :HEAP_TYPES, :TYPE_ORDER

  module_function

  def memsize_of(obj) = Primitive.zr_objspace_memsize(obj)

  def memsize_of_all(klass = nil)
    raise TypeError, "class or module required" unless klass.nil? || klass.is_a?(Module)

    Primitive.zr_objspace_objects(klass).sum { |obj| Primitive.zr_objspace_memsize(obj) }
  end

  def count_objects_size(result = {})
    raise TypeError, "non-hash given" unless result.is_a?(Hash)

    sizes = Hash.new(0)
    Primitive.zr_objspace_objects(nil).each do |obj|
      sizes[heap_type(obj)] += Primitive.zr_objspace_memsize(obj)
    end
    result.clear
    TYPE_ORDER.each { |type| result[:"T_#{type}"] = sizes[type] if sizes.key?(type) }
    result[:TOTAL] = sizes.values.sum
    result
  end

  # Every symbol lives as long as the program: none is mortal.
  def count_symbols(result = {})
    raise TypeError, "non-hash given" unless result.is_a?(Hash)

    total = Symbol.all_symbols.size
    result.update(mortal_dynamic_symbol: 0, immortal_dynamic_symbol: 0, immortal_static_symbol: total, immortal_symbol: total)
  end

  # A program here keeps no parse nodes once it is compiled.
  def count_nodes(result = {})
    raise TypeError, "non-hash given" unless result.is_a?(Hash)

    result
  end

  def count_tdata_objects(result = {})
    raise TypeError, "non-hash given" unless result.is_a?(Hash)

    Primitive.zr_objspace_objects(nil).each do |obj|
      result[obj.class] = result.fetch(obj.class, 0) + 1 if heap_type(obj) == "DATA"
    end
    result
  end

  def count_imemo_objects(result = {})
    raise TypeError, "non-hash given" unless result.is_a?(Hash)

    result
  end

  # A Bignum's class is no reference the collector follows.
  def reachable_objects_from(obj)
    return nil if Primitive.zr_special_p_m(obj)
    return [] if obj.is_a?(Integer)

    Primitive.zr_objspace_reachable(obj)
  end

  def reachable_objects_from_root = Primitive.zr_objspace_roots

  def internal_class_of(obj) = Primitive.zr_real_class(obj)

  def internal_super_of(klass)
    raise TypeError, "wrong argument type #{klass.class} (expected Class or Module)" unless klass.is_a?(Module)

    found = Primitive.zr_objspace_super(klass)
    found.is_a?(Integer) ? InternalObjectWrapper.send(:of, found, :T_ICLASS) : found
  end

  def trace_object_allocations
    raise ArgumentError, "no block given" unless block_given?

    trace_object_allocations_start
    begin
      yield
    ensure
      trace_object_allocations_stop
    end
  end

  def trace_object_allocations_start
    Primitive.zr_alloc_trace_set(true)
  end

  def trace_object_allocations_stop
    Primitive.zr_alloc_trace_set(false)
  end

  def trace_object_allocations_clear = Primitive.zr_alloc_trace_clear

  def trace_object_allocations_debug_start = trace_object_allocations_start

  def allocation_sourcefile(obj) = Primitive.zr_alloc_trace_info(obj)&.at(0)
  def allocation_sourceline(obj) = Primitive.zr_alloc_trace_info(obj)&.at(1)
  def allocation_class_path(obj) = Primitive.zr_alloc_trace_info(obj)&.at(2)
  def allocation_method_id(obj) = Primitive.zr_alloc_trace_info(obj)&.at(3)
  def allocation_generation(obj) = Primitive.zr_alloc_trace_info(obj)&.at(4)

  def _dump(obj, out) = written(out, dumped(obj))

  def _dump_all(out, full, since, shapes)
    lines = Primitive.zr_objspace_objects(nil).filter_map do |obj|
      next unless since.nil? || (allocation_generation(obj) || -1) >= since

      dumped(obj)
    end
    written(out, lines.join)
  end

  # Shapes are CRuby's layout of instance variables; this runtime has none.
  def _dump_shapes(out, since) = written(out, "")

  class << self
    private

    def heap_type(obj)
      HEAP_TYPES.find { |klass, _| obj.is_a?(klass) }&.last || "OBJECT"
    end

    # One object as dump writes it (dump_append_special_const): a special
    # constant as its JSON value, a static Symbol as its name, a flonum in
    # "%#g", and anything else as an object with its address, type and
    # class, on a line of its own.
    def dumped(obj)
      return "null" if obj.nil?
      return obj.to_s if obj == true || obj == false
      if Primitive.zr_special_p_m(obj)
        return obj.to_s if obj.is_a?(Integer)
        return format("%#g", obj) if obj.is_a?(Float)
        return "{\"type\":\"SYMBOL\", \"value\":#{json(obj)}}" if obj.is_a?(Symbol)
      end

      "#{dumped_cell(obj)}\n"
    end

    def dumped_cell(obj)
      fields = { address: address(obj), type: heap_type(obj), class: address(Primitive.zr_real_class(obj)) }
      fields[:frozen] = true if obj.frozen?
      case obj
      when String
        fields.update(bytesize: obj.bytesize, value: obj, encoding: obj.encoding.name)
      when Symbol
        fields.update(bytesize: obj.name.bytesize, value: obj)
      when Float
        fields[:value] = format("%#g", obj)
      when Array, Hash
        fields[:length] = obj.size
      when Module
        fields[:name] = obj.name if obj.name
      end
      fields[:memsize] = Primitive.zr_objspace_memsize(obj)
      "{#{fields.map { |key, value| "#{key.to_s.dump}:#{json(value)}" }.join(', ')}}"
    end

    # "%p": the address in hex, without the zeros in front.
    def address(obj) = format("0x%x", Primitive.zr_any_to_s(obj)[/0x(\h+)/, 1].hex)

    def json(value)
      case value
      when Integer, true, false then value.to_s
      else value.to_s.encode("UTF-8", invalid: :replace, undef: :replace).dump
      end
    end

    def written(out, text)
      out.is_a?(String) ? out << text : out.write(text)
      out
    end
  end
end
