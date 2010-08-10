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
end
