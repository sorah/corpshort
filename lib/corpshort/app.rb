require 'rqrcode'
require 'prawn'
require 'prawn/qrcode'

require 'json'
require 'erubi'
require 'sinatra/base'
require 'rack/protection'

require 'corpshort/link'
require 'corpshort/vertical_pdf'
require 'corpshort/horizontal_pdf'

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

      test = config[:test]
      session = {}
      context = initialize_context(config)
      lambda { |env|
        env['rack.session'] = session if test # FIXME:
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

    use Rack::MethodOverride

    helpers do
      include Prawn::Measurements

      def context
        request.env[CONTEXT_RACK_ENV_NAME]
      end

      def conf
        context.fetch(:config)
      end

      def notice_message
        conf[:notice_message]
      end

      def base_url
        conf[:base_url] || request.base_url
      end

      def short_base_url
        conf[:short_base_url] || base_url
      end


      def backend
        @backend ||= conf.fetch(:backend)
      end

      def random_name
        chars_a = [*('A'..'Z')]
        chars_b = [*('a'..'z'), *('0'..'9')]
        [*1.times.map { |_| chars_a.sample }, *3.times.map { |_| chars_b.sample }].shuffle.join
      end

      def link_name(name = params[:name])
        name.tr('_', '-')
      end

      def short_link_url(link, **kwargs)
        link_url(link, base_url: short_base_url, **kwargs)
      end

      def link_url(link, protocol: true, base_url: self.base_url())
        name = link.is_a?(String) ? link_name(link) : link.name
        "#{base_url}/#{name}".yield_self do |url|
          if protocol
            url
          else
            url.gsub(/\Ahttps?:\/\//, '')
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
        "/+/urls/#{url.sub(%r{://}, '/')}"
      end

      def barcode_path(link, kind, ext, flex: nil)
        "/+/links/#{URI.encode_www_form_component(link.name)}/#{kind}.#{ext}#{flex.nil? ? nil : "?flex=#{flex}"}"
      end

      def render_link_json(link)
        link.as_json.merge(
          show_url: "#{base_url}/#{link.name}+",
          link_url: link_url(link),
          short_link_url: short_link_url(link),
        ).to_json
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
      unless params[:url]
        session[:error] = "Name and URL are required"
        redirect '/'
      end

      @links = backend.list_links_by_url(params[:url])
      if !@links.empty? && !params[:dupe_ack]
        return erb(:duplication_confirm)
      end

      name_given = params[:linkname] && !params[:linkname].strip.empty?
      name = link_name(name_given ? params[:linkname] : random_name)
      retries = 0
      begin
        link = Link.new({name: name, url: params[:url]})
        link.save!(backend, create_only: true)
      rescue Corpshort::Link::ValidationError
        session[:last_form] = {linkname: link.name, url: link.url}
        session[:error] = $!.message
        redirect '/'
      rescue Corpshort::Backends::Base::ConflictError
        if name_given
          session[:last_form] = {linkname: link.name, url: link.url}
          session[:error] = 'Link with the specified name already exists'
          redirect '/'
        else
          name = link_name(random_name)
          retries += 1
          if retries > 20
            session[:error] = 'Could not generate unique name. Try again later.'
            redirect '/'
          else
            sleep 0.1
            retry
          end
        end
      end

      session[:last_form] = nil
      redirect "/#{link.name}+"
    end

    get '/+/links' do
      @links, @next_token = backend.list_links(token: params[:token])
      @title = "Recent links"
      erb :list
    end

    get '/+/links/*name/small.svg' do
      @link = backend.get_link(params[:name])
      halt 404, "not found" unless @link

      content_type :svg
      RQRCode::QRCode.new(link_url(@link), level: params[:level] ? params[:level].to_sym : :m).as_svg(module_size: params[:size] ? params[:size].to_i : 6)
    end
    get '/+/links/*name/small.png' do
      @link = backend.get_link(params[:name])

      halt 404, "not found" unless @link
      content_type :png
      RQRCode::QRCode.new(link_url(@link), level: params[:level] ? params[:level].to_sym : :m).as_png(size: params[:size] ? params[:size].to_i : 120).to_datastream.to_s
    end
    get '/+/links/*name/small.pdf' do
      @link = backend.get_link(params[:name])
      halt 404, "not found" unless @link

      content_type :pdf
      Prawn::Document.new(page_size: [cm2pt(2), cm2pt(2)], margin: 0) do |pdf|
        pdf.fill_color 'FFFFFF'
        pdf.fill { pdf.rounded_rectangle [cm2pt(2), cm2pt(2)], cm2pt(2), cm2pt(2), 10 }
        pdf.print_qr_code(link_url(@link), level: params[:level] ? params[:level].to_sym : :m, extent: cm2pt(2), stroke: false)
      end.render
    end

    get '/+/links/*name/vertical.pdf' do
      @link = backend.get_link(params[:name])
      halt 404, "not found" unless @link

      content_type :pdf

      VerticalPdf.new(
        url: link_url(@link),
        base_url: short_base_url.sub(%r{\A.+://}, ''),
        name: @link.name,
        flex: params[:flex],
      ).document.render
    end

    get '/+/links/*name/horizontal.pdf' do
      @link = backend.get_link(params[:name])
      halt 404, "not found" unless @link

      content_type :pdf
      HorizontalPdf.new(
        url: link_url(@link),
        base_url: short_base_url.sub(%r{\A.+://}, ''),
        name: @link.name,
        flex: params[:flex],
      ).document.render
    end


    get '/+/links/*name/edit' do
      @link = backend.get_link(params[:name])
      if @link
        erb :edit
      else
        halt 404, "not found"
      end
    end

    get '/+/links/*name' do
      redirect "/#{params[:name]}+"
    end

    put '/+/links/*name' do
      @link = backend.get_link(params[:name])
      halt 404, "not found" unless @link

      @link.url = params[:url] if params[:url]

      rename = params[:new_name] && @link.name != params[:new_name]
      if rename
        new_name = link_name(params[:new_name])
        @link = Link.new(name: new_name, url: @link.url)
        # Link.validate_name(new_name)
        # backend.rename_link(@link, new_name)
      end

      begin
        @link.save!(backend, create_only: rename)
      rescue Corpshort::Link::ValidationError, Corpshort::Backends::Base::ConflictError
        session[:error] = $!.message
        redirect "/+/links/#{@link.name}/edit"
      end

      redirect "/#{@link.name}+"
    end

    delete '/+/links/*name' do
      backend.delete_link(params[:name])
      redirect "/"
    end

    get '/+/urls/*url' do
      url = params[:url].sub(%r{\A(https?)/}, '\1://')
      @links, @next_token = backend.list_links_by_url(url), nil
      @title = "Links for URL #{url}"
      erb :list
    end

    ## API

    get '/+api/links' do
      content_type :json
      links, next_token = backend.list_links(token: params[:token])
      {links: links, next_token: next_token}.to_json
    end

    post '/+api/links' do
      content_type :json

      unless params[:name] && params[:url]
        halt 400, '{"error": "missing_params", "error_message": "name and url are required"}'
      end

      if params[:avoid_duplication]
        existing_link = backend.list_links_by_url(params[:url])&.first
        if existing_link
          return render_link_json(backend.get_link(existing_link))
        end
      end

      begin
        link = Link.new({name: link_name, url: params[:url]})
        link.save!(backend, create_only: true)
      rescue Corpshort::Link::ValidationError => e
        halt(400, {error: :validation_error, error_message: e.message}.to_json)
      rescue Corpshort::Backends::Base::ConflictError => e
        halt(409, {error: :conflict, error_message: e.message}.to_json)
      end

      render_link_json(link)
    end

    get '/+api/links/*name' do
      content_type :json
      link = backend.get_link(link_name)
      halt 404, '{"error": "not_found"}' unless link
      render_link_json(link)
    end

    put '/+api/links/*name' do
      content_type :json
      link = backend.get_link(link_name)
      halt 404, '{"error": "not_found"}' unless link
      link.url = params[:url] if params[:url]

      begin
        link.save!(backend)
      rescue Corpshort::Link::ValidationError => e
        halt(400, {error: :validation_error, error_message: e.message}.to_json)
      rescue Corpshort::Backends::Base::ConflictError => e
        halt(409, {error: :conflict, error_message: e.message}.to_json)
      end
      render_link_json(link)
    end

    delete '/+api/links/*name' do
      backend.delete_link(link_name)
      status 202
      ""
    end

    get '/+api/urls' do
      content_type :json
      halt 400, '{"error": "missing_params"}' unless params[:url]
      links = backend.list_links_by_url(params[:url])
      {links: links}.to_json
    end

    get '/+api/urls/*url' do
      content_type :json
      url = params[:url].sub(%r{\A(https?)/}, '\1://')
      links = backend.list_links_by_url(url)
      {links: links}.to_json
    end

    ## Shortlink

    get '/*name' do
      name = params[:name]
      show = name.end_with?('+')
      if show
        name = name[0..-2]
      end

      @link_name = link_name(name)
      @link = backend.get_link(@link_name)

      unless @link
        status 404
        return erb(:'404')
      end

      if show
        erb :show
      else
        redirect @link.url
      end
    end
  end
end
