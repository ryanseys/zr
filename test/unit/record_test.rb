# frozen_string_literal: true

require "test_helper"
require_relative "../../lib/zr/runtime"
require_relative "../../lib/zr/native/build"
require_relative "../../lib/zr/eval/walk/tree"

# Each Record subclass writes its fields out four times: `FIELDS`, the
# accessors, `initialize` and `to_a`. This checks that the four agree.
class RecordTest < Minitest::Test
  RECORDS = ObjectSpace.each_object(Class).select { |klass| klass < Zr::Record && klass.const_defined?(:FIELDS) }
                       .sort_by(&:name).freeze

  def test_every_record_is_found
    assert_operator RECORDS.size, :>, 50
  end

  RECORDS.each do |klass|
    define_method("test_#{klass.name.gsub("::", "_")}_fields_initialize_and_to_a_agree") do
      fields = klass::FIELDS
      record = make(klass)

      assert_equal fields.map(&:to_s), record.to_a, "initialize and to_a take the fields in another order"
      fields.each { |name| assert_equal name.to_s, record.public_send(name), "the reader of #{name}" }
    end
  end

  private

  # A `klass` made through `initialize`, by position or by keyword, where
  # each field contains its own name as a String. A parameter named
  # `next_` sets the field `next`.
  def make(klass)
    positional = []
    keywords = {}
    klass.instance_method(:initialize).parameters.each do |kind, name|
      value = klass::FIELDS.include?(name) ? name.to_s : name.to_s.delete_suffix("_")
      case kind
      when :req, :opt then positional << value
      when :key, :keyreq then keywords[name] = value
      end
    end
    klass.new(*positional, **keywords)
  end
end
