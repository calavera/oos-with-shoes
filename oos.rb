require 'net/http'
require 'digest/md5'
require 'digest/sha1'
require 'rexml/document'
require 'yaml'

class Oos
  
  SCHEME = 'http://'
  HOST = "11870.com"
  API_APP = "calavera-98234798723874"
  API_SECRET_KEY = "76476253912"
  API_PATH = "/api/v1"
  SITES_PATH = "#{API_PATH}/sites"
  PRIVACY_PATH = SCHEME + HOST + API_PATH + '/privacy'
  AUTH_SIGN = Digest::MD5.hexdigest("#{API_APP}#{API_SECRET_KEY}")
  
  AtomNamespace = 'http://www.w3.org/2005/Atom'
  AppNamespace = 'http://www.w3.org/2007/app'
  OosNamespace = 'http://11870.com/api/oos'  
  XhtmlNamespace = 'http://www.w3.org/1999/xhtml'
  GeoRSSNamespace = 'http://www.georss.org/georss/10'
  GmlNamespace = 'http://www.opengis.net/gml'
  OsNamespace = 'http://a9.com/-/spec/opensearch/1.1/'
  XmlNamespaces = {
    'app' => AppNamespace,
    'atom' =>  AtomNamespace,    
    'xhtml' => XhtmlNamespace,
    'oos' => OosNamespace,
    'georss' => GeoRSSNamespace,
    'gml' => GmlNamespace,
    'os' => OsNamespace
  }
  
  AtomEntryContentType = 'application/atom+xml;type=entry'

  attr_accessor :user_mail 
  
  def self.instance
    @@oos ||= Oos.new
  end
  
  def host
    HOST
  end

  def home
    ENV["HOME"] || (ENV["HOMEPATH"] && "#{ENV["HOMEDRIVE"]}#{ENV["HOMEPATH"]}") || "/"
  end

  def request_user(req)
    nonce = Array.new(10){ rand(0x1000000) }.pack('I*')
    nonce_b64 = [nonce].pack("m").chomp
    now = Time.now.gmtime.strftime("%FT%TZ")
    digest = [Digest::SHA1.digest(nonce_b64 + now + credentials[:token])].pack("m").chomp

    req['Authorization'] = 'WSSE realm="11870.com", profile="UsernameToken"'
    req['X-WSSE'] = %Q<UsernameToken Username="#{credentials[:user_mail]}", PasswordDigest="#{digest}", Nonce="#{nonce_b64}", Created="#{now}">
    req
  end

  def request_app(req)      
    req['appToken'], req['authSign'] = API_APP, Digest::MD5.hexdigest("#{API_APP}#{API_SECRET_KEY}")      
    req
  end

  def credentials 
    @credentials ||= (File.exist?("#{home}/credentials.yml"))?
      (YAML::load_file("#{home}/credentials.yml")):nil
  end

  def add_credentials(args = {})
    @credentials = args
    File.open("#{home}/credentials.yml", "w+") do |io|
       io.write(YAML::dump(credentials))
    end
  end

  def connect(host = HOST, ret_body = true, *args)            
    Net::HTTP.start(host) do |http|        
      req = yield      
      
      response = req.class.is_a?(Net::HTTP::Post) ||
          req.class.is_a?(Net::HTTP::Put)?http.request(req, args[0]) :
        http.request(req)        
            
      if response.kind_of?Net::HTTPSuccess
        if ret_body
          return response.body
        else
          return response
        end         
      end      
    end
  end

  def temp_token
    unless @temp_token
      response = connect {
        request_app(Net::HTTP::Get.new("/manage-api/temp-token?appToken=#{API_APP}&authSign=#{AUTH_SIGN}"))
      }      
      @temp_token = response.gsub!(/<(\/)?tempToken>/, '')
    end      
    @temp_token
  end

  def auth_token      
    response = connect {
      request_app(Net::HTTP::Get.new("/manage-api/auth-token?tempToken=#{temp_token}"))
    }

    @auth_token = response.gsub(/<(\/)?authToken>/, '')
    add_credentials({:user_mail => @user_mail, :token => @auth_token})
  end

  def service_document    
    unless @sd
      @sd = REXML::Document.new(connect{request_user(Net::HTTP::Get.new(API_PATH))})
      workspace(@sd)
      slug = sites_collection_href.gsub(SITES_PATH + '/', '')
      add_credentials({:user_mail => credentials[:user_mail], 
          :token => credentials[:token], :slug => slug})
    end
    @sd
  end

  def workspace(sd = service_document.root)
    @wp ||= first(sd, 'workspace')
  end

  def collection(title)
    REXML::XPath.match(workspace, "collection").reject { |col|
      col if (first(col, "atom:title").text != title)
    }.first
  end

  def contacts_collection_href
    @cc_href ||= collection('Contacts').attribute("href").to_s
  end

  def sites_collection_href
    @sc_href ||= collection('Sites').attribute("href").to_s
  end

  def users_collection_href
    @uc_href ||= collection('Users').attribute("href").to_s
  end

  def update_contacts
    @contacts = nil
    contacts
  end
  def contacts        
    @contacts ||= (File.exist?("#{home}/contacts.yml"))?
      (YAML::load_file("#{home}/contacts.yml")):[]
    unless @contacts
      response = connect {
        request_user(Net::HTTP::Get.new(contacts_collection_href))
      }
      contacts_feed = REXML::Document.new(response)
      REXML::XPath.match(contacts_feed.root, 'entry').each do |entry|
        slug = first(entry, "id").text.gsub("#{SCHEME + HOST + contacts_collection_href}/", '')
        contact = {
          :contact => {
            :nick => first(entry, 'title').text,
            :slug => slug,
            :services => contact_services(slug)
          }
        }        
        @contacts << contact        
      end
      File.open("#{home}/contacts.yml", "w+") do |io|
        io.write(YAML::dump(@contacts))
      end
    end    
    @contacts      
  end

  def contact_services(slug)
    response = connect(HOST, false) {request_user(Net::HTTP::Get.new("#{SITES_PATH}/#{slug}"))}
    latest_entry = first(REXML::Document.new(response.body).root, 'entry')
    begin
      review_title = first(latest_entry, 'summary').text if first(latest_entry, 'summary')
      review_content = first(latest_entry, 'content').text if first(latest_entry, 'content')  
      services = {
        :etag => response["ETag"].gsub("\"", ''),
        :latest => {
          :oos_id => first(latest_entry, 'oos:id').text,
          :name => first(latest_entry, 'title').text,
          :edit_link => get_link('edit', latest_entry).to_s,
          :review_title => review_title,
          :review_content => review_content
        }
      }
      services
    rescue
      puts "Error al parsear el servicio: #{$!}"
    end
  end
  
  def search_service(id)
    contacts.reject { |c|            
      c if (c[:contact][:services] && 
          c[:contact][:services][:latest][:oos_id] != id)
    }.first[:contact][:services][:latest]    
  end
  
  def save(id, name, title = nil, content = nil)    
    service = search_service(id)
    
    entry = connect{request_user(Net::HTTP::Get.new("#{sites_collection_href}/#{service[:oos_id]}"))}    
    
    updated = DateTime::now.strftime("%Y-%m-%dT%H:%M:%S%z").sub(/(..)$/, ':\1')
    request = nil
    if (entry)
      request = request_user(Net::HTTP::Put.new(sites_collection_href))
      @entry = REXML::Document.new(entry).root
      first(@entry, 'summary').text = title
      first(@entry, 'content').text = content
      first(@entry, 'updated').text = updated
    else
      request = request_user(Net::HTTP::Post.new(sites_collection_href))
      @entry = create_entry      
      add_element(@entry, 'updated', updated)
      add_element(@entry, 'id', make_id)
      add_element(@entry, 'oos:id', id)
      add_element(@entry, 'title', name)
      add_element(@entry, 'author/name', credentials[:slug])
      add_element(@entry, 'summary', title)
      add_element(@entry, 'content', content)      
      
      add_category(@entry, 'private', PRIVACY_PATH)      
    end
    request.set_content_type(AtomEntryContentType)
    
    if (@entry)      
      response = connect(HOST, true, "<?xml version='1.0' ?>\n" + @entry.to_s) {
        request
      }
      return !response.nil?
    end
    false
  end
  
  def first(*args)
    REXML::XPath.first(args[0], args[1])
  end
  
  def get_link(rel, xml)
    link = first(xml, "./atom:link[@rel=\"#{rel}\"]", XmlNamespaces)
    if link      
      uri = URI.parse link.attributes['href']
      if uri.absolute?
        return uri
      else
        return URI.parse(HOST).merge(uri)
      end      
    end
  end
  
  def create_entry
    entry = REXML::Element.new('entry')
    entry.add_namespace AtomNamespace
    XmlNamespaces.each_pair { |prefix, namespace|
      unless prefix == 'atom' || prefix == 'gml'
        entry.add_namespace prefix, namespace
      end
    }
    entry
  end
  
  def make_id
    id = ''
    5.times { id += rand(1000000).to_s }
    "Oos4ruby:11870.com,2007:#{id}"
  end
  
  def add_element(base, new_el, text, attrs = {})
    elements = new_el.to_s.split("/")
    last = elements[elements.size - 1]
    elements.pop
    root_el = base
    elements.each do |path|
      root_el = base.add_element(path)      
    end
    el = root_el.add_element last.to_s, attrs
    el.text = text
  end
  
  def add_category(base, term, scheme)
    c = REXML::Element.new('category', base)
    c.add_attribute('term', term)
    c.add_attribute('scheme', scheme) if scheme    
  end
end
