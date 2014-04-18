#!/usr/bin/env ruby

# Notes:
#
# The output includes both line items and subtotals. We expect whoever is using this data
# to take care of avoiding double counting. In order to deduplicate the data here we would
# need to guess what the consumer wants to do with the data (does it care about details
# or just chapter subtotals? ...)
#
# We do however remove the programme-level (could be convinced about changing this) and 
# public-body-level subtotals (because they don't fit well with the output file structure).
#
# This is also related to the following. TODO: Expand, and add that in some cases (Social
# Security at least, maybe others) some breakdown stops at the chapter level.
#
# Budget expenses are organized in chapters > articles > concepts > subconcepts. When looking at 
# an expense breakdown, the sum of all the chapters (codes of the form 'n') equals the sum of all 
# articles (codes 'nn') and the sum of all expenses (codes 'nnn'). I.e. the breakdown is exhaustive 
# down to that level. Note however that not all concepts are broken into sub-concepts (codes 'nnnnn'); 
# hence, adding up all the subconcepts will result in a much smaller amount.
#

require 'csv'
require 'bigdecimal'

require_relative 'lib/budget'

budget_id = ARGV[0]
year = budget_id[0..3]  # Sometimes there's a P for 'Proposed' at the end. Ignore that bit
output_path = File.join(".", "output", budget_id)


# RETRIEVE BUDGET LINES
#
# Note: the breakdowns in the Green books (Serie Verde) have more detail on the line
#       items, but they do not include the Social Security programmes. So we need to
#       combine both in order to get the full budget. (Or we could use only the Red ones, 
#       but we'd lose quite a bit of detail. Compare f.ex. the chapter 1/2 detail for
#       programme 333A in the green [1] vs red [2] pages.)
#
# [1]: http://www.sepg.pap.minhap.gob.es/Presup/PGE2013Ley/MaestroDocumentos/PGE-ROM/doc/HTM/N_13_E_V_1_101_1_1_2_2_118_1_2.HTM
# [2]: http://www.sepg.pap.minhap.gob.es/Presup/PGE2013Ley/MaestroDocumentos/PGE-ROM/doc/HTM/N_13_E_R_31_118_1_1_1_1333A_2.HTM
#

def add_line(lines, line, amount)
  lines.push( line.merge({amount: amount}) )
end

def extract_lines(lines, bkdown, open_headings)
  bkdown.expenses.each do |row|
    partial_line = {
      year: bkdown.year,
      section: bkdown.section,
      service: row[:service],
      programme: row[:programme],
      economic_concept: row[:expense_concept],
      description: row[:description]
    }
  
    # The total amounts for service/programme/chapter headings is shown when the heading is closed,
    # not opened, so we need to keep track of the open ones, and print them when closed.
    # TODO: All this may not be needed if we just throw away the chapter-level subtotals, I think
    # (Hmm, but we use that for the other categories, right?)
    if ( row[:amount].empty? )              # opening heading
      open_headings << partial_line
    elsif ( row[:expense_concept].empty? )  # closing heading
      last_heading = open_headings.pop()
      add_line(lines, last_heading, row[:amount]) unless last_heading.nil?
    else                                    # standard data row
      add_line(lines, partial_line, row[:amount])
    end
  end
end

lines = []
Budget.new(budget_id).entity_breakdowns.each do |bkdown|
  # Note: there is an unmatched closing amount, without an opening heading, at the end
  # of the page, containing the amount for the whole section/entity, so we don't start with
  # an empty vector here, we add the 'missing' opening line
  open_headings = [{
    year: bkdown.year,
    section: bkdown.section,
    service: bkdown.is_state_entity? ? '' : bkdown.entity,
    description: bkdown.name
  }]
  extract_lines(lines, bkdown, open_headings)
end

Budget.new(budget_id).programme_breakdowns.each do |bkdown|
  extract_lines(lines, bkdown, [])
end


#
# OUTPUT DATA SPREAD ACROSS A NUMBER OF FILES
#

# Reads a number in spanish notation. Also note input number is in thousands of euros.
def convert_number(amount)
  BigDecimal.new( amount.delete('.').tr(',','.') ) * 1000
end

def get_default_policies_and_programmes
  {
    "0" => { description: "000X" }, # FIXME
    "00" => { description: "000X" },

    "1" => { description: "Servicios públicos básicos" },
    "2" => { description: "Protección y promoción social" },
    "3" => { description: "Bienes públicos de carácter preferente" },
    "4" => { description: "Actuaciones de carácter económico" },
    "9" => { description: "Actuaciones de carácter general" },
    "11" => { description: "Justicia" },
    "12" => { description: "Defensa" },
    "13" => { description: "Seguridad ciudadana e instituciones penitenciarias" },
    "14" => { description: "Política exterior" },
    "21" => { description: "Pensiones" },
    "22" => { description: "Otras prestaciones económicas" },
    "23" => { description: "Servicios sociales y promoción social" },
    "24" => { description: "Fomento del empleo" },
    "25" => { description: "Desempleo" },
    "26" => { description: "Acceso a la vivienda y fomento de la edificación" },
    "29" => { description: "Gestión y administración de la Seguridad Social" },
    "31" => { description: "Sanidad" },
    "32" => { description: "Educación" },
    "33" => { description: "Cultura" },
    "41" => { description: "Agricultura, pesca y alimentación" },
    "42" => { description: "Industria y energía" },
    "43" => { description: "Comercio, turismo y PYMES" },
    "44" => { description: "Subvenciones al transporte" },
    "45" => { description: "Infraestructuras" },
    "46" => { description: "Investigación, desarrollo e innovación" },
    "49" => { description: "Otras actuaciones de carácter económico" },
    "91" => { description: "Alta dirección" },
    "92" => { description: "Servicios de carácter general" },
    "93" => { description: "Administración financiera y tributaria" },
    "94" => { description: "Transferencias a otras admones. públicas" },
    "95" => { description: "Deuda pública" }    
  }
end

# TODO: Because of the way we're extracting Social Security budget, we don't get the 
# list of bodies spending it, so we have to add them manually. Cleaner way of doing this?
def get_default_bodies
  # TODO: Double check these are correct, got them from an old DVMI hack
  bodies = {}
  bodies[get_entity_id('60', nil)] = { description: "Seguridad Social" }
  bodies[get_entity_id('60', '1')] = { description: "Pensiones y Prestaciones Económicas de la Seguridad Social" }
  bodies[get_entity_id('60', '2')] = { description: "Prest. Asistenciales, Sanitarias Y Sociales Del Ingesa Y Del Inserso" }
  bodies[get_entity_id('60', '3')] = { description: "Dirección Y Serv. Generales De Seguridad Social Y Protección Social" }
  bodies
end

# The entity id is now five digits: section(2)+service(3, zero filled)
def get_entity_id(section, service)
  return section if service.nil? or service.empty?
  section+service.rjust(3, '0')
end

# Collect categories first, then output, to avoid duplicates
CSV.open(File.join(output_path, "estructura_economica.csv"), "w", col_sep: ';') do |csv|
  categories = {}
  lines.each do |line|
    concept = line[:economic_concept]
    next if concept.nil? or concept.empty?
    next if concept.length > 2  # FIXME
    categories[concept] = line
  end

  csv << ["EJERCICIO", "GASTO/INGRESO", "CAPITULO", "ARTICULO", "CONCEPTO", "SUBCONCEPTO", "DESCRIPCION CORTA", "DESCRIPCION LARGA"]
  categories.sort.each do |concept, line|
    csv << [year, 
            "G",
            concept[0], 
            concept.length >= 2 ? concept[0..1] : nil,
            nil,  # FIXME
            nil,  # FIXME
            nil,  # Short description, not used
            line[:description] ]
  end
end

CSV.open(File.join(output_path, "estructura_financiacion.csv"), "w", col_sep: ';') do |csv|
  csv << ["EJERCICIO", "GASTO/INGRESO", "ORIGEN", "FONDO", "FINANCIACION", "DESCRIPCION CORTA", "DESCRIPCION LARGA"]
  csv << [year, "G", "X", "XX", "XXX", "Gastos", ""]
end

# Collect programmes first, then output, to avoid duplicates
CSV.open(File.join(output_path, "estructura_funcional.csv"), "w", col_sep: ';') do |csv|
  programmes = get_default_policies_and_programmes
  lines.each do |line|
    programme = line[:programme]
    next if programme.nil? or programme.empty?
    next unless line[:economic_concept].nil? or line[:economic_concept].empty?
    programmes[programme] = line
  end

  csv << ["EJERCICIO","GRUPO","FUNCION","SUBFUNCION","PROGRAMA","DESCRIPCION CORTA","DESCRIPCION LARGA"]
  programmes.sort.each do |programme, line|
    csv << [year,
            programme[0],
            programme.length >= 2 ? programme[0..1] : nil,
            programme.length >= 3 ? programme[0..2] : nil,
            programme.length >= 4 ? programme : nil,
            nil,  # Short description, not used
            line[:description] ]
  end
end

CSV.open(File.join(output_path, "estructura_organica.csv"), "w", col_sep: ';') do |csv|
  bodies = get_default_bodies
  lines.each do |line|
    next unless line[:programme].nil? or line[:programme].empty?
    bodies[get_entity_id(line[:section], line[:service])] = line
  end

  csv << ["EJERCICIO","CENTRO GESTOR","DESCRIPCION CORTA","DESCRIPCION LARGA"]
  bodies.sort.each do |body_id, line|
    csv << [year,
            body_id,
            nil,  # Short description, not used
            line[:description]]
  end
end

CSV.open(File.join(output_path, "gastos.csv"), "w", col_sep: ';') do |csv|
  expenses = []
  lines.each do |line|
    next if line[:economic_concept].nil? or line[:economic_concept].empty?
    next if line[:economic_concept].length > 2  # FIXME: missing low level data

    line[:body_id] = get_entity_id(line[:section], line[:service])  # Convenient
    expenses.push line
  end

  csv << ["EJERCICIO","CENTRO GESTOR","FUNCIONAL","ECONOMICA","FINANCIACION","DESCRIPCION","IMPORTE"]
  expenses.sort do |a,b| 
    [a[:programme], a[:body_id], a[:economic_concept]] <=> [b[:programme], b[:body_id], b[:economic_concept]]
  end.each do |expense|
    csv << [year, 
            expense[:body_id],
            expense[:programme], 
            expense[:economic_concept], 
            'XXX', 
            expense[:description],
            convert_number(expense[:amount]).to_int ]
  end
end

CSV.open(File.join(output_path, "ingresos.csv"), "w", col_sep: ';') do |csv|
  csv << ["EJERCICIO","CENTRO GESTOR","ECONOMICA","FINANCIACION","DESCRIPCION","IMPORTE"]
end

