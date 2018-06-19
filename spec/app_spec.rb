require 'corpshort/app'
require 'corpshort/backends/memory'


RSpec.describe Corpshort::App do
  before(:all) do
    Corpshort::App.set :environment, :test
  end
  def app
    Rack::Builder.new do 
      run Corpshort::App.rack(
        test: true,
        base_url: 'http://example.com',
        backend: Corpshort::Backends::Memory.new(),
      )
    end
  end

  describe "GET /" do
    it "returns 200" do
      get '/'
      expect(last_response.status).to eq 200
    end
  end
end
