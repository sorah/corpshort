require 'corpshort/backends/memory'
require 'corpshort/link'

RSpec.describe Corpshort::Backends::Memory do
  let(:backend) { described_class.new() }
  let(:link) { Corpshort::Link.new({url: 'https://example.org', name: 'test'}) }

  describe "#put_link" do
    it "creates link" do
      backend.put_link(link)
      expect(backend.links[link.name][:url]).to eq link.url
    end
    it "updates link" do
      backend.put_link(link)
      link.url = 'https://example.com'
      backend.put_link(link)
      expect(backend.links[link.name][:url]).to eq link.url
    end
    context "with create_only" do
      it "raises an error when a link conflicts" do
        backend.put_link(link, create_only: true)
        expect {
          backend.put_link(link, create_only: true)
        }.to raise_error(Corpshort::Backends::Base::ConflictError)
      end
    end
  end

  describe "#get_link" do
    it "returns a link" do
      backend.put_link(link)
      expect(backend.get_link(link.name).url).to eq link.url
    end
    context "when link doesn't exist" do
      it "returns nil" do
        expect(backend.get_link("aaaa")).to be_nil
      end
    end
  end

  describe "#delete_link" do
    it "deletes a link" do
      backend.put_link(link)
      backend.delete_link(link.name)
      expect(backend.links[link.name]).to be_nil
    end
  end

  describe "#list_links_by_url" do
    it "returns a list of links for a URL" do
      backend.put_link(Corpshort::Link.new({url: 'https://example.org', name: 'a'}))
      backend.put_link(Corpshort::Link.new({url: 'https://example.org', name: 'b'}))
      backend.put_link(Corpshort::Link.new({url: 'https://example.com', name: 'c'}))
      expect(backend.list_links_by_url('https://example.org').sort).to eq %w(a b)
    end
  end

  describe "#list_links" do
    it "returns a list of links" do
      backend.put_link(Corpshort::Link.new({url: 'https://example.org', name: 'a'}))
      backend.put_link(Corpshort::Link.new({url: 'https://example.org', name: 'b'}))
      backend.put_link(Corpshort::Link.new({url: 'https://example.com', name: 'c'}))

      links, _token = backend.list_links()
      expect(links.sort).to eq %w(a b c)
    end
  end
end
