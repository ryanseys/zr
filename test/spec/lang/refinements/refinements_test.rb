# frozen_string_literal: true

require "spec_helper"

describe "Refinements programs" do
  it "refine block sees its sibling refinements" do
    result = ze0(<<~'RUBY')
      # Inside a refine block, every refinement the same module holds is in use,
      # the ones written after it too, as rb_mod_refine shares the module's
      # activated refinements. REXML's Array#dclone calls dclone on a Symbol
      # that way.
      module Clones
        refine Object do
          def dup_of = [:object, clone]
        end
        refine Symbol do
          def dup_of = [:symbol, self]
        end
        refine Array do
          def dup_of = map { |v| v.dup_of }
          def both = [1.dup_of, 1.later]
        end
        refine Integer do
          def later = :integer_seen_from_array
        end
      end
      using Clones
      p [:a, "s"].dup_of
      p [].both

    RUBY

    _(result).must_answer <<~'OUT'
      [[:symbol, :a], [:object, "s"]]
      [[:object, 1], :integer_seen_from_array]
    OUT
  end
end
