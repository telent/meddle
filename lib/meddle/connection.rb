
# pop each transaction off the queue and replay it.  If there is a delay
# before the next request should be sent, add a timer to wait that long

# The connection is open until we run out of queue or we exceed the
# max idle time +persistent_request_timeout+ or the peer closes it

# If the connection closes for any reason other than end of queue, add
# a timer for another Connection to be created later and continue the
# job

class Meddle::Connection < EM::Connection

  def self.start(queue,options)
    uri=URI.parse(queue.peek[1].request.uri)
    EM.connect(uri.host,uri.port,self,:queue=>queue,*options)
  end

  def initialize *args
    o=args[0]
    @queue=o[:queue]
    @persistent_request_timeout=o[:persistent_request_timeout] || 150
    @state=:idle
    super
  end
  
  def post_init
    begin
      uri=@queue.peek[1].request.uri 
      if uri.scheme.upcase == "HTTPS" then
        start_tls
      end
      send_next_request
    rescue Exception => e
      warn e
      raise e
    end
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
    @state=:sending
    @tx=tx
    r=tx.request
    uri=URI.parse(r.uri)
    p=uri.path
    if q=uri.query then
      p << "?" << q
    end
        
    # XXX for now we are hardcoding http version 1.0 so no bugger
    # gives us chunked bodies that we're not expecting.  This needs
    # fixed
    send_data "#{r.method.upcase} #{p} HTTP/1.0\r\n" 
    h=r.header

    # recalculate the request content length: it may have changed if
    # user code has altered the body, or if Firefox was chunking (we
    # don't do request chunking) or if reconstituting the body from
    # XML has caused it to change length
    h["Content-Length"]=[r.body.bytesize.to_s]

    # we disable keepalives even if the orginal session was using
    # them.  We will fix this at some point
    h["Connection"]=["close"]
    h.each do |k,v|
      v.each do |v|
        send_data "#{k}: #{v}\r\n"
      end
    end
    send_data "\r\n"

    if(["POST","PUT"].member?(r.method)) then
      send_data r.body
      end
    @data=''
    @header=Hash.new { |hash,k| hash[k]=[] }
    @state=:waiting
  end

  def process_body(data)
    warn "Received #{body.bytesize} octets of body content"
  end

  def process_header(data)
    warn "#{@tx.request.method} #{@tx.request.uri} #{status[1]} #{headers['Content-Length'][0] or "???"}"
  end

  def receive_data(data)
    if @state=:waiting then @state=:rx_header end
    @data += data
    case @state
    when :rx_header then
      # XXX is there a blank line after the headers even in cases where
      # no body?  must check
      end_headers=@data.index("\r\n\r\n") 
      if end_headers then 
        header_text=@data.slice(0,hdrs_end)
        @data=@data.slice(hdrs_end+2)
        StringIO.open(header_text,"r") do |fin|
          status=fin.readline.chomp.split(/ /,3) 
          while (line=fin.gets) 
            k,v=line.split(/:/)
            v and @header[k] << v.chomp.strip
          end
        end
        header[:http_status]=status
        process_header(header)
        # XXX we make no attempt to receive chunked-encoding bodies,
        # and we should do
        @state=:recv_body 
      end
    when :recv_body then
      if @data.bytesize >= @headers['Content-Length'] then
        process_body(@data)
        @state=:idle
        @tx=nil
      end
    when :idle then
      warn "Received data while in :idle state, what gives?"
    end
  end
  
  def unbind
    unless @state == :idle
      warn "Unexpected connection close by peer"
    end
    run_time,tx=@queue.peek
    if tx then
      EM.add_timer (run_time-Time.now) {
        Connection.start(queue,
                         :persistent_request_timeout=>@persistent_request_timeout)
      }
    end
  end
end
