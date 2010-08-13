require 'meddle'
require 'trollop'

opts=Trollop::options do
  opt :profile, "Profile the run using ruby-prof"
  opt :profile_graph, "Profile output file", :default=>"callgraph.prof"
  opt :dry_run, "Show the script, don't run it", :short=>'-n'
end

opts[:profile] and require 'ruby-prof'

class BasketPurchase < Meddle::Session
  script_file "rq-registered-success.xml" do |tx|
    r=tx.request
    h=r.header["Host"]
    if h[0] == "www.dev.stargreen.com" then
      r.uri.host="localhost.stargreen.com"
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

if opts[:dry_run] then
  b=BasketPurchase.new
  b.each do |tx|
    print "#{tx.request.method} #{tx.request.uri.to_s} #{tx.request.body}\n"
  end
  exit 0
end

begin
  EM.run do
    meddle=Meddle::Agent.new do |agent|
      10.times do |i| 
        agent.add_session BasketPurchase.new
        agent.add_session BasketPurchase.new,2
        agent.add_session BasketPurchase.new,5
        agent.add_session BasketPurchase.new,7
        agent.add_session BasketPurchase.new,15
        agent.add_session BasketPurchase.new,20
        agent.add_session BasketPurchase.new,30
        agent.add_session BasketPurchase.new,40
        agent.add_session BasketPurchase.new,51
        agent.add_session BasketPurchase.new,65
      end
    end
    warn "running until #{meddle.finish_time}"
    EM.add_timer(meddle.finish_time-Time.now+5) do
      EM.stop
    end
    opts[:profile] && RubyProf.start
  end
rescue Exception => e
  raise e
ensure 
  if opts[:profile] then
    result = RubyProf.stop
    
    printer = RubyProf::GraphPrinter.new(result)
    File.open(opts[:profile_graph],"w") do |f|
      printer.print(f, {})
    end
    printer = RubyProf::FlatPrinter.new(result)
    printer.print(STDOUT, {})
  end
end
