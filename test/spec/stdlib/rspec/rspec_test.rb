# frozen_string_literal: true

require "spec_helper"

describe "RSpec programs" do
  it "reports a failure" do
    skip "rspec is not installed: neither engine has it, so there is nothing to compare"

    result = zr(<<~'RUBY')

      # XFAIL: rspec renders a failing or pending example by extracting the source
      # snippet for the line that raised, and `RSpec::Support::Source#ast` does that
      # with `require "ripper"`.
      #
      # That was once the reason this file was held back, and it is no longer
      # true: `rt/ext/ripper.so.rb` answers `require "ripper"` over
      # `Prism::Translation::Ripper`, and `test/spec/stdlib/ripper/` holds it to
      # ruby. What holds this back now is that rspec is not installed -- it is
      # deliberately not vendored, and both engines are meant to read the same
      # copy -- so there is nothing here to compare against.
      #
      # A suite whose examples all pass never reaches that path, which is what
      # `../an_rspec_suite_runs.rb` holds. This file is the other half: the day zeo
      # can answer `require "ripper"`, or rspec stops needing it, this starts
      # matching and the suite says so.

      require "stringio"
      real_stdout = $stdout
      $stdout = StringIO.new
      at_exit do
        report = $stdout.string
        $stdout = real_stdout
        print report.gsub(/Finished in .*/, "Finished in <time>")
      end

      require "rspec/autorun"

      RSpec.describe "arithmetic" do
        it "reports a failure" do
          expect(1).to eq(2)
        end

        it "is pending" do
          pending "not yet"
          raise "still broken"
        end
      end
    RUBY

    _(result).must_answer <<~'OUT', status: 1
      F*
      
      Pending: (Failures listed here are expected and do not affect your suite's status)
      
        1) arithmetic is pending
           # not yet
           Failure/Error: raise "still broken"
      
           RuntimeError:
             still broken
           # ./milestones/pending/rspec_reports_a_failure.rb:35:in 'block (2 levels) in <main>'
      
      Failures:
      
        1) arithmetic reports a failure
           Failure/Error: expect(1).to eq(2)
      
             expected: 2
                  got: 1
      
             (compared using ==)
           # ./milestones/pending/rspec_reports_a_failure.rb:30:in 'block (2 levels) in <main>'
      
      Finished in <time>
      2 examples, 1 failure, 1 pending
      
      Failed examples:
      
      rspec ./milestones/pending/rspec_reports_a_failure.rb:29 # arithmetic reports a failure
      
    OUT
  end

  it "a real suite runs and reports its examples, matchers, doubles, hooks, counts and exit status" do
    skip "rspec is not installed: neither engine has it, so there is nothing to compare"

    result = zr(<<~'RUBY')

      # MILESTONE: a REAL rspec suite, written the way anyone writes one, runs under
      # zeo and reports what rspec reports -- examples, matchers, doubles, hooks,
      # the counts and the exit status.
      #
      # A failing or a pending example renders through `RSpec::Support::Source`,
      # which asks for `ripper`; zr answers that over
      # `Prism::Translation::Ripper`. The other half of this file holds that.
      #
      # Both engines read the SAME rspec, from `vendor/bundle` -- the Gemfile.lock
      # set that `make deps` resolves. The oracle reaches it through
      # bundler, zeo through `-I` on each gem's `lib/`. That makes this a true
      # differential rather than a recording: neither engine has rspec of its own,
      # and comparing zeo against nothing would prove nothing.
      #
      # rspec is deliberately NOT vendored under `gems/`. Everything there is a
      # library ruby itself ships, so a `require` reaches the same code on both
      # sides; vendoring rspec would make zeo answer a require ruby refuses.
      #
      # rspec prints a duration that cannot match across two engines, so an
      # `at_exit` registered BEFORE rspec's rewrites that one line -- handlers are
      # LIFO, so this sees the finished report. Everything else is compared byte for
      # byte.
      #
      # Shapes, never versions -- see `tests/milestones.rs`.

      require "stringio"
      real_stdout = $stdout
      $stdout = StringIO.new
      at_exit do
        report = $stdout.string
        $stdout = real_stdout
        print report.gsub(/Finished in .*/, "Finished in <time>")
      end

      require "rspec/autorun"

      RSpec.describe "arithmetic" do
        let(:values) { [1, 2, 3] }
        subject { values.sum }

        it "sums" do
          expect(subject).to eq(6)
        end

        it "maps" do
          expect(values.map { |v| v * 2 }).to eq([2, 4, 6])
        end

        it "raises" do
          expect { 1 / 0 }.to raise_error(ZeroDivisionError)
        end

        context "with matchers" do
          it "matches strings" do
            expect("hello").to match(/ell/)
            expect("hello").to start_with("he")
            expect(%w[a b]).to include("a")
            expect(values).to all(be_a(Integer))
            expect(values).to contain_exactly(3, 2, 1)
          end

          it "negates" do
            expect(values).not_to be_empty
            expect(values.first).not_to be_nil
            expect(values).to have_attributes(size: 3)
          end
        end

        describe "hooks" do
          before(:each) { @seen = "before" }
          after(:each)  { @seen = nil }

          it "sees the hook" do
            expect(@seen).to eq("before")
          end
        end

        describe "doubles" do
          it "stubs and verifies" do
            thing = double("thing", size: 2)
            expect(thing.size).to eq(2)

            spy = double("spy")
            allow(spy).to receive(:call).and_return(:ok)
            expect(spy.call).to eq(:ok)
            expect(spy).to have_received(:call)
          end
        end
      end
    RUBY

    _(result).must_answer <<~'OUT'
      .......

      Finished in <time>
      7 examples, 0 failures

    OUT
  end
end
