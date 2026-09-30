# Through a relay that has a `begin`/`ensure` -- no `return` of its own, so it
# has nothing to catch.
def ensured
  begin
    yield 9
  ensure
    nil
  end
  :fell
end
def c5; ensured { |v| return v }; :no; end
p c5

