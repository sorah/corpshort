require 'erubi'
require 'sinatra/base'
require 'rack/protection'

require 'corpshort/link'

require 'uri'

module Corpshort
  def self.app(*args)
    App.rack(*args)
  end

  class App < Sinatra::Base
    CONTEXT_RACK_ENV_NAME = 'corpshort.ctx'

    def self.initialize_context(config)
      {
        config: config,
      }
    end

    def self.rack(config={})
      klass = App

      context = initialize_context(config)
      lambda { |env|
        env[CONTEXT_RACK_ENV_NAME] = context
        klass.call(env)
      }
    end

    configure do
      enable :logging
    end

    set :root, File.expand_path(File.join(__dir__, '..', '..', 'app'))
    set :erb, :escape_html => true

    use Rack::Protection::FrameOptions
    use Rack::Protection::HttpOrigin
    use Rack::Protection::IPSpoofing
    use Rack::Protection::JsonCsrf
    use Rack::Protection::PathTraversal
    use Rack::Protection::RemoteToken, only_if: -> (env) { ! env['PATH_INFO'].start_with?('/+api') }
    use Rack::Protection::SessionHijacking
    use Rack::Protection::XSSHeader

    helpers do
      def context
        request.env[CONTEXT_RACK_ENV_NAME]
      end

      def conf
        context.fetch(:config)
      end

      def base_url
        conf[:base_url] || request.base_url
      end

      def backend
        @backend ||= conf.fetch(:backend)
      end

      def link_name(name = params[:name])
        name.tr('_', '-')
      end

      def link_url(link, protocol: true)
        name = link.is_a?(String) ? link_name(link) : link.name
        "#{base_url}/#{name}".yield_self do |url|
          if protocol
            url
          else
            url.gsub(/^https:\/\//, '')
          end
        end
      end

      def edit_path(link)
        "/+/links/#{URI.encode_www_form_component(link.name)}/edit"
      end

      def update_path(link)
        "/+/links/#{URI.encode_www_form_component(link.name)}"
      end

      def urls_path(url)
        "/+/urls/#{url}"
      end
    end

    get '/' do
      erb :index
    end

    ## Pages

    get '/+' do
      if params[:show]
        redirect "/+/links/#{link_name(params[:show])}"
      end
      halt 404
    end

    post '/+/links' do
      unless params[:name] && params[:url]
        session[:error] = "Name and URL are required"
        redirect '/'
      end

      begin
        link = Link.new({name: link_name, url: params[:url]})
        link.save!(backend, create_only: true)
      rescue Corpshort::Link::ValidationError, Corpshort::Backends::Base::ConflictError
        session[:error] = $!.message
        redirect '/'
      end

      redirect "/#{link.name}+"
    end

    get '/+/links' do
      @links, @next_token = backend.list_links(token: params[:token])
      @title = "Recent links"
      erb :list
    end

    get '/+/links/:name' do
      redirect "/#{params[:name]}+"
    end

    get '/+/links/:name/svg' do
    end
    get '/+/links/:name/png' do
    end
    get '/+/links/:name/pdf' do
    end

    get '/+/links/:name/edit' do
      @link = backend.get_link(params[:name])
      if @link
        erb :edit
      else
        halt 404, "not found"
      end
    end

    put '/+/links/:name' do
      @link = backend.get_link(params[:name])
      @link.url = params[:url] if params[:url]
      @link.save!

      if @link.name != params[:new_name]
        new_name = link_name(params[:new_name])
        backend.rename_link(@link, new_name)
        redirect "/#{new_name}+"
      else
        redirect "/#{@link.name}+"
      end
    end

    delete '/+/links/:name' do
      backend.delete_link(params[:name])
      redirect "/"
    end

    get '/+/urls/*url' do
      url = env['REQUEST_URI'][8..-1]
      @links, @next_token = backend.list_links_by_url(url), nil
      @title = "Links for URL #{url}"
      erb :list
    end

    ## API

    get '/+api/links' do
    end

    get '/+api/links/:name' do
    end

    get '/+api/urls/*url' do
    end

    put '/+api/links/:name' do
    end

    ## Shortlink

    get '/:name' do
      name = params[:name]
      show = name.end_with?('+')
      if show
        name = name[0..-2]
      end

      @link = backend.get_link(link_name(name))

      unless @link
        halt 404, 'not found'
      end

      if show
        erb :show
      else
        redirect @link.url
      end
    end
  end
end
