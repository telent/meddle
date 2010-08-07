require 'meddle'

session=Meddle::Session.new("rq-registered-success.xml")
session.replay do |tx|
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

# we don't yet have any code that stops EM, so this bit never runs

exit 0

PP.pp(session.select {|tx|
        tx.request.method == "POST" && 
        tx.request.uri.match(/dev.stargreen/) &&
        tx.request.body.match(/STANDING/)
      })
