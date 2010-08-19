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
    attr_accessor :uri,:method,:uri_text
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
      nodeset.map do |n|
        URI::unescape(n['name']) + ": " +
          URI::unescape(n.child.content.strip)
      end
    end
    
    def self.from_xml(node)
      rq_headers=node.css('tdRequestHeaders tdRequestHeader')
      rs_headers=node.css('tdResponseHeaders tdResponseHeader')
      body=node.css('tdPostElements tdPostElement').map { |n|
        [URI::unescape(n['name']),URI::unescape(n.child.content.strip)].join "="
      }.join("&")         
      
      url=URI::unescape(node['uri'])
      url_parsed=
        begin 
          URI.parse(url)
        rescue URI::InvalidURIError
          URI.parse('about:badurl')
        end
      headers=read_headers(rq_headers)
      self.new(:request=>Request.new(:uri=>url_parsed,
                                     :uri_text=>url,
                                     :method=>kid(node,'tdRequestMethod'),
                                     :header=>headers,
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
