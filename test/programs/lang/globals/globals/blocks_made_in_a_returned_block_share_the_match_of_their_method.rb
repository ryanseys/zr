# Blocks made in a block that has returned, and called later, share $~
# with the scope further out, as CRuby keeps it in the method's env.
$blocks = []
def describe(&b) = b.call
def before(&b) = $blocks << b
def it(&b) = $blocks << b
describe do
  before { "mis-matched" =~ /s(-)m(.)/ }
  it { p [defined?($~), defined?($1), $2] }
end
o = Object.new
$blocks.each { |b| o.instance_eval(&b) }
$blocks.each(&:call)
