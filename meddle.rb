require 'nokogiri'
require 'pp'
require 'uri'
require 'eventmachine'

module Meddle
  module NamedInitialize
    def initialize(args)
      args.each { |k,v| self.send("#{k}=",v)}
    end
  end
  
  class Message
    attr_accessor :header,:body
    include NamedInitialize
  end
  
  class Request < Message
    attr_accessor :uri,:method
  end
  
  class Response < Message
    attr_accessor :status
  end
  
  class EmConnect < EM::Connection
    def initialize *args
      super
      @tx=args[0][:transaction]
      @start=args[0][:start]
      @offset=args[0][:offset]
    end

    def post_init
      r=@tx.request
      uri=URI.parse(r.uri)
      p=uri.path
      if q=uri.query then
        p << "?"
        p << q
      end

      if uri.scheme.upcase == "HTTPS" then
        start_tls
      end

      send_data "#{r.method.upcase} #{p} HTTP/1.0\r\n"
      h=r.header
      # recalculate the content length in case reconstituting the body from
      # XML has caused it to change length - or the body has been altered 
      # by user code
      h["Content-Length"]=[r.body.bytesize.to_s]
      # we are disabling keepalives even if the orginal session was done 
      # with them.  We could stand to fix this at some point
      h["Connection"]=["close"]
      begin
        h.each do |k,v|
          v.each do |v|
            send_data "#{k}: #{v}\r\n"
          end
        end
      rescue Exception => e
        warn e
        raise e
      end
      send_data "\r\n"
      if(["POST","PUT"].member?(r.method)) then
        send_data r.body
      end
      @data=''
    end

    def receive_data(data)
      @data += data
    end
    def unbind 
      headers=Hash.new { |hash,k| hash[k]=[] }
      status=["HTTP/1.1","510","No response"]
      unless @data.empty?
        hdrs_end=@data.index("\r\n\r\n") 
        if hdrs_end == nil 
          header_text,body=[@data,nil]
        else
          header_text,body=[@data.slice(0,hdrs_end),@data.slice(hdrs_end+2)]
        end
        StringIO.open(header_text,"r") do |fin|
          status=fin.readline.chomp.split(/ /,3) 
          while (line=fin.gets) 
            k,v=line.split(/:/)
            v and  headers[k] << v.chomp.strip
          end
        end
      end
      warn "#{@offset}/#{Time.now-@start} "+
        "#{@tx.request.method} #{@tx.request.uri} #{status[1]} #{headers['Content-Length'][0] or "???"}"
    end
  end

  class Transaction 
    include NamedInitialize
    attr_accessor :request,:response,:start_time,:elapsed_time,
    :total_elapsed_time,:xml_path
    def self.kid(node,name)
      node.css(name)[0].child.content
    end
    def self.read_headers(nodeset)
      headers=Hash.new {|hash,key| hash[key]=[] }
      nodeset.each do |n|
        headers[URI::unescape(n['name'])].
          push(URI::unescape(n.child.content.strip))
      end
      headers
    end
      
    def self.from_xml(node)
      rq_headers=node.css('tdRequestHeaders tdRequestHeader')
      rs_headers=node.css('tdResponseHeaders tdResponseHeader')
      body=read_headers(node.css('tdPostElements tdPostElement')).map do |k,v|
        "#{k}=#{v.join}"          # XXX doesn't work if multiple fields with
      end.join("&")               # same name
      
      self.new(:request=>Request.new(:uri=>(URI::unescape(node['uri'])),
                                     :method=>kid(node,'tdRequestMethod'),
                                     :header=>read_headers(rq_headers),
                                     :body=>body),
               # if we're discarding detail that a client might want, 
               # we do at least save the original node xpath so they can 
               # dig it out themselves
               :xml_path=>node.path,
               :start_time=>Time.at(kid(node,'tdStartTimeMS').to_i/1000.0),
               # dunno which of these is which - perhaps download time
               # vs render time?
               :elapsed_time=>kid(node,'tdElapsedTime').to_i,
               :total_elapsed_time=>kid(node,'tdTotalElapsedTime').to_i,
               :response=>Response.new(:status=>node.css('tdStatus')[0].child.content.to_i,
                                       :header=>read_headers(rs_headers))
               )
    end
  end
  class Session
    include Enumerable
    def each(&blck)
      @transactions.each(&blck)
    end
    def [](index)
      @transactions[index]
    end
    def initialize(file)
      doc=File.open(file) do |f|
        Nokogiri::XML(f)
      end
      @transactions=doc.root.css('tdRequest').map {|x| Transaction.from_xml(x)}
    end
    def replay
      orig_start_time=@transactions[0].start_time
      orig_end_time=@transactions[-1].start_time
      start=Time.now
      EventMachine::run do
        EM.add_timer(orig_end_time-orig_start_time+5) do 
          EM.stop
        end
        @transactions.each do |tx|
          if yield(tx) then
            offset=tx.start_time-orig_start_time
            EM.add_timer(offset) do 
              EM.next_tick do # not sure if this line necessary, but ...
                url=URI.parse(tx.request.uri)
                EM.connect url.host,url.port,EmConnect,:transaction=>tx,
                :start=>start,:offset=>offset
              end
            end
          end
        end
      end
    end
  end
end
