
class Meddle::Session 
  attr_accessor :agent
  include Enumerable
  def each(&blck)
    @transactions.each(&blck)
  end
  def [](index)
    @transactions[index]
  end

  # This method takes a block that it yields to for each transaction,
  # which may change the request (headers, body) as it wishes and
  # return the modified version, or may return a falsey value to
  # discard this transaction from the session.  Note that the block
  # runs at the start of the test session so is useful only for
  # "constant" changes - it cannot modify later requests in the light
  # of responses from earlier ones, because the earlier ones have not
  # yet happened.

  # Discarding transactions may be useful for example if the session
  # includes requests to hosts other than the hosts under test (e.g.
  # google analytics)

  # See also #munge_request 

  def self.script_file(file)
    doc=File.open(file) do |f|
      Nokogiri::XML(f)
    end
    txs=doc.root.css('tdRequest').map {|x| Meddle::Transaction.from_xml(x)}
    @transactions=txs.map do |tx|
      yield (tx) and tx
    end.reject(&:nil?)
  end
  class << self; attr_reader :transactions; end

  def initialize
    @transactions=self.class.transactions
  end

  # This runs when the request is due to be sent, so stored data from
  # earlier requests (e.g. the values of Set-Cookie headers) can be
  # sent using munge_request on later requests.
  
  # If your application requires runtime efficiency, your #munge_request 
  # method should be runtime-efficient :-)
  
  def munge_request(tx)
    [tx.request.header,tx.request.body]
  end

  def check_response_header(tx,status,h)
    code= status.split(/ /)[1].to_i
    if code >=400  then
      warn "\n#{tx.request.uri} #{status}"
    else
      $stderr.print "."
    end
  end

  # if you are getting responses full of binary guck instead of the 
  # plain text you were hoping for, one possibility is that the 
  # original browsing session was between a client and server that
  # support gzip or deflate compression.  Your options are either
  # to remove Accept-Encoding from the request headers before sending
  # (see #munge_headers) or for a more realistic test use Zlib::Inflate
  # or similar to decompress it yourself.  

  # If you are testing the ETag headers returned by the server, note
  # that changing the Accept-Encoding header is likely to change them.
  # See e.g. http://httpd.apache.org/docs/2.2/mod/core.html#fileetag

  def check_response_body(tx,status,h,b)
    l= h['Content-Length']
    if l[0] && (l[0] != b.bytesize)
      warn "received #{b.bytesize} body bytes, expecting l[0]"
    end
  end

end
