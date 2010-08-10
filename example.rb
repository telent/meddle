require 'meddle'

EM.run do
  meddle=Meddle::Agent.new do |agent|
    session=Meddle::Session.new("rq-registered-success.xml") do |tx|
      r=tx.request
      h=r.header["Host"]
      if h[0] == "www.dev.stargreen.com" then
        r.uri.gsub!(/www.dev.stargreen.com/,"localhost.stargreen.com")
        r.header["Host"]=["localhost.stargreen.com"]
        tx
      end
    end
    agent.add_session session
    agent.add_session session,2
    agent.add_session session,5
  end
end
