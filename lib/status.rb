class Status
  include DataMapper::Resource

  property :id,         Serial
  property :value,      Boolean,  :required => true
  property :updated_at, DateTime, :required => true
  property :uri,        String,   :required => true

  validates_presence_of :value, :message => 'Value must not be blank'
  validates_presence_of :updated_at, :message => 'Timestamp must not be blank'
  
  
  # Public: Updates a node with a status
  #
  # node - The Node object
  #
  # Returns true on success, otherwise false
  def self.update(node)
    begin
      response = RestClient.get node.uri
      status = response.code == 200
    rescue => ex
      status = false
    end
    result = self.create(:updated_at => Time.now, :value => status, :uri => node.uri)
    result.saved?
  end
  
  
  # Public: Get the current status of all nodes
  #
  # Returns Array of statuses for every node with data
  def self.current
    statuses = Array.new
    Node.all.each do |uri|
      n = Node.new(uri)
      s = self.first(:uri => uri, :order => [ :updated_at.desc ], :limit => 1)
      next unless s
      statuses << { :timestamp => s.updated_at, :status => s.value, :uri => n.uri, :host => n.host }
    end
    statuses
  end
  
  
  # Public: Get the uptime for the given period and node
  #
  # start_time The Time start
  # end_time   The Time end
  # node       The Node object
  #
  # Returns String uptime of the node or nil if statuses not found
  def self.uptime(start_time, end_time, node)
    uptimes   = 0
    downtimes = 0
    
    self.all(:uri => node.uri, :updated_at.gte => start_time, :updated_at.lte => end_time).each do |status|
      uptimes   += 1 if  status.value
      downtimes += 1 if !status.value
    end
    
    return nil if uptimes == 0 && downtimes == 0
    
    # Availability = (Uptime / (Uptime + Downtime)) x 100
    '%.2f' % ((uptimes.to_f / (uptimes + downtimes).to_f ) * 100.0)
  end
  
  
  # Public: Get status feeds from external service
  #
  # Currently supports only RSS feeds
  # 
  # since The Time since feed
  #
  # Returns hash representation of feed data
  # Returns empty hash on errors
  # Returns empty hash if no feeds since time given
  def self.feeds(since = nil)
    
    feed = {}
    
    begin
      rss       = SimpleRSS.parse open(APP_CONFIG['feeds_url'])
      feed_item = nil
      
      rss.items.each do |item|
        next if item.empty?
        
        author = parse_feed_item(:author, item.send(APP_CONFIG['feeds_item_author']))
        next unless APP_CONFIG['feeds_authors_whitelist'].include?(author)
        
        published_at = parse_feed_item(:date,   item.send(APP_CONFIG['feeds_item_date']))
        content      = parse_feed_item(:author, item.send(APP_CONFIG['feeds_item_author']))
        link         = parse_feed_item(:link,   item.send(APP_CONFIG['feeds_item_link']))
        break
      end
      
      return feed if since.is_a?(Time) && published_at.to_i < since.to_i
      
      {:date => published_at, :author => author, :content => content, :link => link}
    rescue
      feed
    end
  end
  
  
  private
    
    def parse_feed_item(item, value)
      case item.to_s
      when 'date'
        Time.parse(value.to_s)
      when 'author'
        # First Last\n   email
        value.gsub(/\n.*/, '')
      when 'content'
        # remove links
        value.gsub(/<a.*<\/a>/, '')
      end
    end
  
end
