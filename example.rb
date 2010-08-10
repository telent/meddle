require 'meddle'

meddle=Meddle::Agent.new do |agent|
  session=Meddle::Session.new("rq-registered-success.xml") do |tx|
    r=tx.request
    h=r.header["Host"]
    if h[0] == "www.dev.stargreen.com" then
      r.uri.gsub!(/www.dev.stargreen.com/,"localhost.stargreen.com")
      r.header["Host"]=["localhost.stargreen.com"]
      true
    else
      false
    end
  end
  agent.add_session session
  agent.add_session session,2
  agent.add_session sessio n,5
end

