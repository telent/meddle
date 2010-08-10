
class Meddle::Session 
  include Enumerable
  def each(&blck)
    @transactions.each(&blck)
  end
  def [](index)
    @transactions[index]
  end

  # new accepts a block which is called for each transaction. It may
  # change the request (headers, body) as it wishes and return the
  # modified version, or may return a falsey value to discard this
  # transaction from the session.  

  # Discarding transactions may be useful for example if the session
  # includes requests to hosts other than the hosts under test (e.g.
  # google analytics)
  def initialize(file)
    doc=File.open(file) do |f|
      Nokogiri::XML(f)
    end
    txs=doc.root.css('tdRequest').map {|x| Transaction.from_xml(x)}
    @transactions=txs.map { |tx| (yield tx) || nil }.reject(&:nil?)
  end
end
