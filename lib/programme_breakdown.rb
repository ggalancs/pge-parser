#!/usr/bin/env ruby

require 'nokogiri'
require 'open-uri'
require_relative 'base_breakdown'

# Parser for programme expense breakdowns (Serie Roja / Red books), i.e. pages like [1].
#
# Note: for some unknown reason, chapter 6 items are not broken down into articles. This 
#       seems to happen everywhere, not just for Social Security or for a particular programme
#       (f.ex. [2]). Bizarrely, the 'programme summaries' [3] do contain the chapter 6 breakdown,
#       but many other details are missing: compare [3] with [1]. At the moment we do not try 
#       to combine [1] and [3] to get the full picture, we learn to live with [1] instead, 
#       and thank our burocratic overlords.
#
# XXX: This parser will only work -now- with Social Security (section 60) programmes. See below.
#
# [1]: http://www.sepg.pap.minhap.gob.es/Presup/PGE2013Ley/MaestroDocumentos/PGE-ROM/doc/HTM/N_13_E_R_31_2_1_G_1_1_1312B_P.HTM
# [2]: http://www.sepg.pap.minhap.gob.es/Presup/PGE2013Ley/MaestroDocumentos/PGE-ROM/doc/HTM/N_13_E_R_31_116_1_1_1_1131M_2.HTM
# [3]: http://www.sepg.pap.minhap.gob.es/Presup/PGE2013Ley/MaestroDocumentos/PGE-ROM/doc/HTM/N_13_E_R_31_2_1_G_1_1_1312B_O.HTM
#
class ProgrammeBreakdown < BaseBreakdown
  attr_reader :year, :programme

  def initialize(filename)
    filename =~ PROGRAMME_EXPENSES_BKDOWN
    @year = '20'+$1
    @programme = $2         # Programme id (of the form '123A')
    @filename = filename
  end
  
  def section
    doc.css('.S0ESTILO3').first.text.strip =~ /^Sección: (\d\d) .+$/
    $1
  end

  def programme_name
    doc.css('.S0ESTILO3').last.text.strip =~ /^Programa: \d\d\d\w (.+)$/
    $1
  end

  # Returns a list of budget items and subtotals. Because of the convoluted format of the 
  # input file, with subtotals being split across two lines, some massaging is needed.
  def expenses
    merge_subtotals(data_grid, year, section)
  end

  def self.programme_breakdown? (filename)
    filename=~PROGRAMME_EXPENSES_BKDOWN
  end
  
  private

  # Returns a list of column arrays containing all the information in the input data table,
  # basically unmodified, apart from two columns (service, programme) filled in, since
  # in the input grid they are only shown when they change
  def data_grid
    data_grid = []
    last_service = ''

    # Iterate through HTML table, skipping header
    rows = doc.css('table.S0ESTILO8 tr')[1..-1]               # 2008 onwards (earlier?)
    rows.map do |row|
      columns = row.css('td').map{|td| td.text.strip}
      item = {
        # XXX: If you see [4] above, not Social Security, it's actually xx.xxx. And
        #   there are probably x.xx out there somewhere. We'll need to fix this
        #   in order to use this parser for non-Social-Security programmes.
        :service => columns[0].slice(3..4), # section.service comes in the form xx.xx
        :programme => @programme, 
        :expense_concept => columns[1], 
        :description => columns[2],
        :amount => (columns[3] != '') ? columns[3] : columns[4] 
      }
      next if item[:description].empty?  # Skip empty lines (no description)

      # Fill blanks in row and save result
      if item[:service].nil?
        item[:service] = last_service
      else
        last_service = item[:service]
        
        # Bit of a hack (again). We want the subtotals from this breakdown to look like
        # the ones extracted from an EntityBreakdown, but here the data is presented
        # as programme>entity>item, while there they look like entity>programme>item.
        # So we need to change the subtotal description to include the programme name.
        item[:description] = programme_name
      end
      data_grid << item      
    end
    data_grid
  end

  PROGRAMME_EXPENSES_BKDOWN =      /N_(\d\d)_[AE]_R_31_2_1_G_1_1_1(\d\d\d\w)_P.HTM/;
  # Note:                                              ^ 
  #       This will catch only Social Security programme breakdowns (see Budget class for info).
  #       It's what I need for now. Note it doesn't pick up internal transfers either. 
  
  def doc
    @doc = Nokogiri::HTML(open(@filename)) if @doc.nil?  # Lazy parsing of doc, only when needed
    @doc
  end
end