
# pop each transaction off the queue and replay it.  If there is a delay
# before the next request should be sent, add a timer to wait that long

# The connection is open until we run out of queue or we exceed the
# max idle time +persistent_request_timeout+ or the peer closes it

# If the connection closes for any reason other than end of queue, add
# a timer for another Connection to be created later and continue the
# job

class Meddle::Connection < EM::Connection

  def self.start(queue,session,options={})
    time,tx=queue.peek
    if tx then
      uri=tx.request.uri
      EM.connect(uri.host,uri.port,self,options.merge(:queue=>queue,:session=>session))
    end
  end

  def initialize *args
    o=args[0]
    @queue=o[:queue]
    @session=o[:session]
    @persistent_request_timeout=o[:persistent_request_timeout] || 150
    @state=:idle
    super
  end
  
  def post_init
    begin
      uri=@queue.peek[1].request.uri 
      if uri.scheme.upcase == "HTTPS" then
        @state=:tls
        start_tls
      else
        send_next_request
      end
    rescue Exception => e
      warn e
      warn e.backtrace
      raise e
    end
  end

  def ssl_handshake_completed
    @state=:idle
    send_next_request
  end
  
  def send_next_request
    run_time,tx=@queue.pop
    if tx.nil?
      close_connection    
    else
      delay=run_time-Time.now
      if delay>0.1 then
        if delay > @persistent_request_timeout then
          # no more work for this connection.  Make EM call #unbind which
          # will arrange for a new one to be created later
          @queue.push([run_time,tx])
          close_conection
        else 
          EM.add_timer (delay) {
            self.send_request(tx)
          }
        end
      else
        self.send_request(tx)
      end
    end
  end

  def send_request(tx)
    header,body=@session.munge_request(tx)
    if header.nil? then 
      return self.send_next_request
    end
    @state=:sending
    @tx=tx
    r=tx.request
    uri=r.uri
    p=uri.path
    if q=uri.query then
      p << "?" << q
    end
        
    # XXX for now we are hardcoding http version 1.0 so no bugger
    # gives us chunked bodies that we're not expecting.  This needs
    # fixed
    send_data "#{r.method.upcase} #{p} HTTP/1.0\r\n" 
 
    send_data header.join("\r\n")
    send_data "\r\n\r\n"
    if(["POST","PUT"].member?(r.method)) then
      # XXX is this the right test?  perhaps we should send the body if there
      # is one irrespective of method
      send_data r.body
      end
    @data=''
    @header=Hash.new { |hash,k| hash[k]=[] }
    @state=:waiting
  end

  def process_body
    @session.check_response_body(@tx,@http_status,@header,@data)
  end

  def process_header
    @session.check_response_header(@tx,@http_status,@header)
  end
  
  def parse_headers(end_headers)
    header_text=@data.slice(0,end_headers)
    @data=@data.slice(end_headers+4,@data.length)
    @http_status=[]
    # profiling says that StringIO is much faster than I was expecting
    # (i.e. basically negligible CPU use). which is nice
    StringIO.open(header_text,"r") do |fin|
      @http_status=fin.readline.chomp
      while (line=fin.gets) 
        k,v=line.split(": ")
        v and @header[k] << v.chomp
      end
    end
  end

  def receive_data(data)
    if @state==:waiting then @state=:rx_header end
    @data += data
    case @state
    when :rx_header then
      # XXX is there a blank line after the headers even in cases where
      # no body?  must check
      end_headers=@data.index("\r\n\r\n") 
      if end_headers then 
        parse_headers(end_headers)
        self.process_header
        # XXX we make no attempt to receive chunked-encoding bodies,
        # and we should do
        l=@header['Content-Length']
        if (l[0] && (l[0].to_i == 0)) then
          # if content-length is present and 0 then we assume it's 
          # a 204 No content, or something
          @state=:idle
        else
          # if the header is missing altogether then body length is unknown
          # and we just have to keep going until the peer hangs up
          @state=:rx_body 
          # if we got the header and body in one call to receive_data,
          # go round again to make sure the body gets processed
          if(@data.bytesize > 0)
            return receive_data('')
          end
        end
      end
    when :rx_body then
      l=@header['Content-Length']
      if l[0] && (@data.bytesize >= l[0].to_i) then
        self.process_body
        @state=:idle
        @tx=nil
        if @header['Connection'][0] == 'close' then
          self.close_connection
        else 
          self.send_next_request
        end
      end
    when :idle then
      u="unknown"
      if @tx then u=@tx.request.uri end
      warn "#{u} received #{data} while in :idle state, what gives?"
    when :tls then
      warn "Received data while in :tls - is this supposed to happen?"
    else
      warn "Unhandled case #{@state}"
    end
  end
  
  def unbind
    if @state == :rx_body then
      self.process_body
      @state=:idle
    end
    unless @state == :idle
      warn "Unexpected connection close by peer in state #{@state}"
    end
    run_time,tx=@queue.peek
    if tx then
      EM.add_timer (run_time-Time.now) {
        Meddle::Connection.start(@queue,@session,
                                 :persistent_request_timeout=>@persistent_request_timeout)
      }
    end
  end
end
