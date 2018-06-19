require 'prawn'
require 'prawn/qrcode'

module Corpshort
  class VerticalPdf
    include Prawn::Measurements

    def initialize(url:, base_url:, name:, flex: false)
      @url = url
      @base_url = base_url
      @name = name

      @flex = flex

      if @flex
        @width = code_size + required_width_for_url_box + padding + padding
      end
    end

    def w
      @width || cm2pt(6)
    end

    def h
      cm2pt(4)
    end

    def code_size
      cm2pt(3)
    end

    def padding
      cm2pt(0.2)
    end

    def text
      [
        {link: @url, text: @base_url},
        {link: @url, text: '/'},
        {link: @url, styles: [:bold], text: @name},
      ]
    end

    def required_width_for_url_box
      doc = Prawn::Document.new(page_size: [cm2pt(5),cm2pt(5)], margin: 0)
      doc.font_size = 12
      text.inject(0) do |r,t|
        r + doc.width_of(t.fetch(:text), style: t[:styles]&.first)
      end
    end

    def url_box
      Prawn::Text::Formatted::Box.new(
        text,
        document: pdf,
        at: [padding, (h-code_size)-padding],
        width: w - padding - padding,
        height: (h-code_size) - padding - padding,
        overflow: :shrink_to_fit,
        min_font_size: nil,
        disable_wrap_by_char: true,
        align: :center,
        valign: :center,
        kerning: true,
      )
    end

    def render
      @pdf = nil

      code_pos = [(w-code_size)/2.0, h]

      pdf.fill_color 'FFFFFF'
      pdf.fill { pdf.rounded_rectangle code_pos, code_size, code_size, 5 }
      pdf.print_qr_code(@url, level: :m, pos: code_pos, extent: code_size, stroke: false)

      [true, false].each do |dry_run|
        box = url_box()
        box.render(dry_run: dry_run)
        if dry_run
          pdf.fill_color 'FFFFFF'
          pdf.fill do
            pdf.rounded_rectangle(
              [box.at[0] - padding, box.at[1] + padding],
              box.available_width + padding + padding,
              box.height + padding + padding,
              5,
            )
          end
          pdf.fill_color '000000'
        end
      end

      pdf
    end

    def document
      render
    end

    def pdf
      @pdf ||= Prawn::Document.new(page_size: [w,h], margin: 0).tap do |pdf|
        pdf.font_size = 12
      end
    end
  end
end
