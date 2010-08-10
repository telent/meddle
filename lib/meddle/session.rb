
class Meddle::Session 
  attr_reader :start_time_offset
  include Enumerable
  def each(&blck)
    @transactions.each(&blck)
  end
  def [](index)
    @transactions[index]
  end
  def initialize(file,options)
    doc=File.open(file) do |f|
      Nokogiri::XML(f)
    end
    @transactions=doc.root.css('tdRequest').map {|x| Transaction.from_xml(x)}
    @orig_start_time=@transactions[0].start_time
    @start_time_offset=options[:delay] || 0
  end
end
