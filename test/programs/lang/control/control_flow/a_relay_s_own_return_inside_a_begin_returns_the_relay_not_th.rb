# Through a relay that has a `return` of its own INSIDE the begin: it really
# does catch, and must still tell the two apart.
def both
  begin
    yield 7
    return :inner
  rescue StandardError
    :r
  end
end
def c7; both { |v| return v }; :no; end
p c7
p both { :ignored }

