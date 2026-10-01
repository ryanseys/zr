# StringScanner matches its pattern at the scan pointer. CRuby hands the
# compiled pattern the text and the pointer; here each scan copies the
# rest of the text and compiles the pattern again behind a \A, so a
# tokenizer over a long text is quadratic in its length.
require "strscan"
src = "foo = bar(12, 'baz') + 3.5 * qux # note\n" * 1_000
count = 0
ss = StringScanner.new(src)
until ss.eos?
  if ss.skip(/\s+/) then next
  elsif ss.scan(/[a-z_]\w*/) then count += 1
  elsif ss.scan(/\d+(\.\d+)?/) then count += 1
  elsif ss.scan(/'[^']*'/) then count += 1
  elsif ss.scan(/#.*$/) then count += 1
  else ss.getch; count += 1
  end
end
p count

