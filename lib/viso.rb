# Viso
# ------
#
# **Viso** is the magic that powers [CloudApp][] by displaying shared Drops. At
# its core, **Viso** is a simple [Sinatra][] app that retrieves a **Drop's**
# details using the [CloudApp API][]. Images are displayed front and center,
# bookmarks are redirected to their destination, markdown is processed by
# [RedCarpet][], code files are highlighted by [Pygments], and, when all else
# fails, a download button is provided. **Viso** uses [eventmachine][] and
# [rack-fiber_pool][] to serve requests while expensive network I/O is performed
# asynchronously.
#
# [cloudapp]:        http://getcloudapp.com
# [sinatra]:         https://github.com/sinatra/sinatra
# [cloudapp api]:    http://developer.getcloudapp.com
# [redcarpet]:       https://github.com/tanoku/redcarpet
# [pygments]:        http://pygments.org
# [eventmachine]:    https://github.com/eventmachine/eventmachine
# [rack-fiber_pool]: https://github.com/mperham/rack-fiber_pool
require 'addressable/uri'
require 'eventmachine'
require 'metric_recorder'
require 'sinatra/base'
require 'simpleidn'

require 'configuration'
require 'drop'
require 'drop_fetcher'
require 'drop_presenter'
require 'domain'
require 'domain_fetcher'

require 'base64'

class Viso < Sinatra::Base
  register Configuration

  # The home page. Custom domain users have the option to set a home page so
  # ping the API to get the home page for the current domain. Response is cached
  # for one hour.
  get '/' do
    cache_control :public, :max_age => 3600
    redirect DomainFetcher.fetch(env['HTTP_HOST']).home_page
  end

  # Record metrics sent by JavaScript clients.
  get '/metrics' do
    MetricRecorder.record params['name'], params['value']
    content_type 'text/javascript'
    status 200
  end

  # The main responder for a **Drop**. Responds to both JSON and HTML and
  # response is cached for 15 minutes.
  get %r{^                         #
         (?:/(text|code|image))?   # Optional drop type
         /([^/?#]+)                # Item slug
         (?:                       #
           /  |                    # Ignore trailing /
           /o                      # Show original image size
         )?                        #
         $}x do |type, slug|
    fetch_and_render_drop slug
  end

  get %r{^
         /([^/?#]+)  # Item slug
         /status
         $}x do |slug|
    fetch_and_render_status slug
  end

  # Legacy endpoint used at one time for A/B performance testing. It was only
  # active for 24 hours but it lives on embedded on websites. Keep this around
  # for a while and either roll it into the primary content route or delete it
  # if it's unused.
  get %r{^/content                #
         (?:/(text|code|image))?  # Optional drop type
         /([^/?#]+)               # Item slug
         /([^/?#]+)               # Encoded url
         $}x do |type, slug, encoded_url|
    begin
      decoded_url = Base64.urlsafe_decode64(encoded_url)
    rescue
      not_found
    end

    http = EM::HttpRequest.
             new("http://#{ DropFetcher.base_uri }/#{ slug }/view").
             apost
    http.callback {
      if http.response_header.status != 201
        puts [ '#' * 5,
               http.last_effective_url,
               http.response_header.status,
               '#' * 5
             ].join(' ')
      end
    }
    http.errback {
      puts [ '#' * 5,
             http.last_effective_url,
             'ERR',
             '#' * 5
           ].join(' ')
    }
    redirect decoded_url
  end

  # The download link for a **Drop**. Response is cached for 15 minutes.
  get %r{^                         #
         (?:/(text|code|image))?   # Optional drop type
         /([^/?#]+)                # Item slug
         /download
         /(.+)       # Filename
         $}x do |type, slug, filename|
    redirect_to_api
  end

  # The content for a **Drop**. Response is cached for 15 minutes.
  get %r{^                         #
         (?:/(text|code|image))?   # Optional drop type
         /([^/?#]+)                # Item slug
         /(.+)       # Filename
         $}x do |type, slug, filename|
    respond_to {|format|
      format.html do
        fetch_and_render_content slug, filename
      end
      format.json do
        fetch_and_render_drop slug
      end
    }
  end

  # Don't need to return anything special for a 404.
  not_found do
    not_found error_content_for(:not_found)
  end

  def redirect_to_content(drop)
    http = EM::HttpRequest.
             new("http://#{ DropFetcher.base_uri }/#{ drop.slug }/view").
             apost
    http.callback {
      if http.response_header.status != 201
        puts [ '#' * 5,
               http.last_effective_url,
               http.response_header.status,
               '#' * 5
             ].join(' ')
      end
    }
    http.errback {
      puts [ '#' * 5,
             http.last_effective_url,
             'ERR',
             '#' * 5
           ].join(' ')
    }
    redirect drop.remote_url
  end

protected

  # Fetch and return a **Drop** with the given `slug`. Handle
  # `DropFetcher::NotFound` errors and render the not found response.
  def fetch_drop(slug)
    timer = Metriks.timer('viso.drop.fetch').time
    DropFetcher.fetch slug
  rescue DropFetcher::NotFound
    not_found
  ensure
    timer.stop
  end

  def fetch_and_render_drop(slug)
    timer = Metriks.timer('viso.drop').time
    drop = DropPresenter.new fetch_drop(slug), self

    check_domain_matches drop

    Metriks.timer("viso.drop.render.#{ drop.item_type }").time {
      respond_to {|format|
        format.html { drop.render_html }
        format.json { drop.render_json }
      }
    }
  rescue => e
    env['async.callback'].call [ 500, {}, error_content_for(:error) ]
    Airbrake.notify_or_ignore e if defined? Airbrake
  ensure
    timer.stop
  end

  def fetch_and_render_content(slug, filename)
    drop = fetch_drop slug
    # check_domain_matches drop
    # check_filename_matches drop, filename
    redirect_to_content drop
  end

  def fetch_and_render_status(slug)
    drop = DropPresenter.new fetch_drop(slug), self
    status drop.pending? ? 204 : 200
  end

  def error_content_for(type)
    type = type.to_s.gsub /_/, '-'
    File.read File.join(settings.public_folder, "#{ type }.html")
  end

  # Check for drops served where the drop's domain doesn't match the accessed
  # domain. For example, a user using another user's custom domain.
  def check_domain_matches(drop)
    unless custom_domain_matches? drop
      puts [ '*' * 5,
             drop.data[:url].inspect,
             env['HTTP_HOST'].inspect,
             '*' * 5
           ].join(' ')

      not_found
    end
  end

  def custom_domain_matches?(drop)
    domain   = Addressable::URI.parse(drop.data[:url]).host
    host     = env['HTTP_HOST'].split(':').first
    expected = SimpleIDN.to_ascii(domain).downcase
    actual   = SimpleIDN.to_ascii(host).downcase

    DropFetcher.default_domains.include?(actual) or
      actual == expected or
      actual.sub(/^www\./, '') == expected
  end

  # Redirect the current request to the same path on the API domain.
  def redirect_to_api
    cache_control :public, :max_age => 900
    redirect "http://#{ DropFetcher.base_uri }#{ request.path }"
  end
end
