require 'meddle'
require 'trollop'

opts=Trollop::options do
  opt :num_clients, "Number of clients to start", :default=>1,:short=>'-c'
  opt :staggered_start, "Delay each client start time by up to n seconds", :default=>60
  opt :dry_run, "Show the script, don't run it", :short=>'-n'
  opt :profile, "Profile the run using ruby-prof"
  opt :profile_graph, "Profile output file", :default=>"callgraph.prof"
end

opts[:profile] and require 'ruby-prof'

class BasketPurchase < Meddle::Session
  script_file "rq-registered-success.xml" do |tx|
    r=tx.request
    h=r.header["Host"]
    if h[0] == "www.dev.stargreen.com" then
      r.uri.host="localhost.stargreen.com"
      r.header["Host"]=["localhost.stargreen.com:#{r.uri.port}"]
      tx
    end
  end

  def munge_request(tx) 
    r=tx.request
    r.header["Cookie"]=[@cookie].compact
    r.header.delete "Accept-Encoding"
    if r.uri.path.match /checkout/ then
      warn r.body
    end
    tx
  end

  def check_response_header(tx,status,header)
#    super
    if(l=header['Set-Cookie'][0]) then
      @cookie=(l.split /;/)[0]
      warn "got cookie! #{@cookie}"
    end
    $stderr.print "."
  end
  def check_response_body(tx,status,header,body)
    ct=header['Content-Type']    
    begin
      if ct[0].index('text/html') and (status.split[1].to_i < 400) then
        body.scan( %r{<TITLE.+?>(.+?)<} ) do |w|
          warn "#{tx.request.uri.to_s} #{ct[0]} #{w[0]}"
        end
        if status.split[1].to_i < 400 then
          raise "body missing for #{tx.request.uri.to_s}" unless
            body.scan /All trademarks are acknowledged/
        end
      end
    rescue Exception => e
      raise e
    end
  end
end

if opts[:dry_run] then
  b=BasketPurchase.new
  b.each do |tx|
    print "> #{tx.request.method} #{tx.request.uri.to_s} #{tx.request.body}\n"
    print "< #{tx.response.header}"
  end
  exit 0
end

srand()

begin
  EM.run do
    meddle=Meddle::Agent.new do |agent|
      opts[:num_clients].times do |i| 
        agent.add_session BasketPurchase.new, 
        (i==0) ? 0 : rand()*opts[:staggered_start]
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
