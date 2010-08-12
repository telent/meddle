require 'meddle'

class BasketPurchase < Meddle::Session
  script_file "rq-registered-success.xml" do |tx|
    r=tx.request
    h=r.header["Host"]
    if h[0] == "www.dev.stargreen.com" then
      r.uri.gsub!(/www.dev.stargreen.com/,"localhost.stargreen.com")
      r.header["Host"]=["localhost.stargreen.com"]
      tx
    end
  end

  def munge_request(tx) 
    r=tx.request
    if @cookie then
      cookie=header["Cookie"][0]
      header["Cookie"]=[cookie.gsub(/\;\s+stargreen_session=[\w\.]+/,@cookie)]
    end
    tx
  end

  def check_response_header(tx,status,header)
    super
    if(l=header['Set-Cookie'][0]) then
      warn "got cookie! #{l}"
      @cookie=l
    end
  end
  def check_response_body(tx,status,header,body)
    ct=header['Content-Type']
    if ct[0]=='text/html' then
      raise "body missing" unless body.match /&copy; 1999-2010/
    end
  end
end

EM.run do
  meddle=Meddle::Agent.new do |agent|
    1.times do |i| 
      p=BasketPurchase.new
      agent.add_session p
      #agent.add_session BasketPurchase.new,2
      #agent.add_session BasketPurchase.new,5
    end
  end
  warn "running until #{meddle.finish_time}"
  EM.add_timer(meddle.finish_time-Time.now+5) do
    EM.stop
  end
end
