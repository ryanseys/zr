# frozen_string_literal: true

require "test_helper"
require_relative "../../lib/ze0/zr"
require_relative "../../lib/ze0/native/build"

# A unit assembled in workers: the answers in item order whatever the
# bins, the first failure in item order, and the bytes of the kernel's
# object the same for one process and for three.
class ParallelTest < Minitest::Test
  def test_answers_come_back_in_item_order_for_any_jobs
    items = (1..40).to_a
    [1, 2, 3, 7].each do |jobs|
      assert_equal items.map { |x| x * x }, Ze0::Native::Parallel.map(items, jobs: jobs, weight: ->(x) { x % 5 }) { |x| x * x }
    end
  end

  def test_a_failure_raises_the_first_items_error
    error = assert_raises(ArgumentError) do
      Ze0::Native::Parallel.map((1..30).to_a, jobs: 3, weight: ->(x) { x }) do |x|
        raise TypeError, "late #{x}" if x == 25
        raise ArgumentError, "first #{x}" if x == 11

        x
      end
    end
    assert_equal "first 11", error.message
  end

  def test_the_kernel_object_is_the_same_bytes_from_any_number_of_workers
    one, three = [1, 3].map do |jobs|
      unit = Ze0::Machine.unit(Ze0::Zr.kernel_files)
      image = Ze0::Native::Build.unit(unit.functions, unit.data, raw: unit.raw, export: true, jobs: jobs, floor: 0)
      Ze0::Native::Build.writer(Ze0::Target.default).write(image)
    end
    assert_equal one.bytesize, three.bytesize
    assert one == three, "the kernel object differs between one worker and three"
  end
end
