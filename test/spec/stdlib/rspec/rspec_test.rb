# frozen_string_literal: true

require "spec_helper"

describe "Rspec programs" do
  it "reports a failure" do
    skip "rspec renders a failing example by extracting its source with ripper, which ze0 declines"

    result = ze0(<<~'RUBY', path: "stdlib/rspec/rspec_reports_a_failure.rb")

      # XFAIL: rspec renders a failing or pending example by extracting the source
      # snippet for the line that raised, and `RSpec::Support::Source#ast` does that
      # with `require "ripper"`.
      #
      # zeo declines ripper on purpose: it exposes the reduction event stream of
      # CRuby's parse.y, and zeo's front end embeds prism -- a different parser with
      # a different event model, so there is nothing to bind. rspec asks for it
      # unconditionally on CRuby, deciding from RUBY_VERSION rather than probing, so
      # the LoadError escapes through the formatter and the run dies after the
      # progress dots.
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

    _(result).must_answer "F*\n\nPending: (Failures listed here are expected and do not affect your suite's status)\n\n  1) arithmetic is pending\n     # not yet\n     Failure/Error: raise \"still broken\"\n\n     RuntimeError:\n       still broken\n     # ./milestones/pending/rspec_reports_a_failure.rb:35:in 'block (2 levels) in <main>'\n\nFailures:\n\n  1) arithmetic reports a failure\n     Failure/Error: expect(1).to eq(2)\n\n       expected: 2\n            got: 1\n\n       (compared using ==)\n     # ./milestones/pending/rspec_reports_a_failure.rb:30:in 'block (2 levels) in <main>'\n\nFinished in <time>\n2 examples, 1 failure, 1 pending\n\nFailed examples:\n\nrspec ./milestones/pending/rspec_reports_a_failure.rb:29 # arithmetic reports a failure\n\n", status: 1
  end

  it "rspec suite runs" do
    skip "rspec renders a suite through RSpec::Support::Source, which needs ripper, and ze0 declines ripper"

    result = ze0(<<~'RUBY')

      # MILESTONE: a REAL rspec suite, written the way anyone writes one, runs under
      # zeo and reports what rspec reports -- examples, matchers, doubles, hooks,
      # the counts and the exit status.
      #
      # No FAILING or PENDING example here: rspec renders those by extracting the
      # source snippet, which needs `ripper`, and zeo declines ripper (prism has a
      # different event model -- see docs/COMPATIBILITY.md). That half is
      # `pending/rspec_reports_a_failure.rb`.
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
