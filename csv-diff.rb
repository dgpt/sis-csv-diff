#!/usr/env/ruby

# Takes an old CSV and a new CSV and outputs any new data in the new CSV in the form of a CSV.
# csv-diff <old-csv> <new-csv> -o <output-file> => <changes>

module CSVDiff
  require "csv"

  def self.diff(old_path, new_path)
    require "sqlite3"

    # Load CSVs from provided paths (cross-platform)
    old_csv = CSV.read(File.expand_path(old_path))
    new_csv = CSV.read(File.expand_path(new_path))

    p "Finished loading files."

    # Get CSV headers
    old_header, new_header = [old_csv, new_csv].map(&:first)
    header = old_header # pointless, but clearer

    # Check for errors
    throw "Headers do not match." unless old_header == new_header

    # Create new CSV array (to be later written to file)
    diff = [header]

    p "Calculating changes between CSV files..."
    begin
      db = SQLite3::Database.new ':memory:'

      sql_table_headers = header.collect { |h| h + ' TEXT' }.join(', ')

      db.execute 'CREATE TABLE new_csv(id INTEGER PRIMARY KEY AUTOINCREMENT, ' << sql_table_headers << ')'
      db.execute'CREATE TABLE old_csv(id INTEGER PRIMARY KEY AUTOINCREMENT, ' << sql_table_headers << ')'

      insert_query = proc { |table, row|
        sql_row = row.join('\', \'').chomp(', ')
        sql_header = header.join(', ').chomp(', ')
        sql_binds = ('?, ' * row.length).chomp(', ')

        'INSERT INTO ' << table << ' (' << sql_header << ') VALUES (' << sql_binds << ')'
      }

      db.transaction do |trans|
        new_csv.each do |r|
          query = insert_query.call('new_csv', r)
          trans.query(query, r)
        end

        old_csv.each do |r|
          query = insert_query.call('old_csv', r)
          trans.query(query, r)
        end
      end

      join_statement = header.collect { |a| "n.#{a} = o.#{a}" }.join(' AND ')
      res = db.execute "SELECT n.id AS new_id, o.id AS old_id FROM new_csv AS n INNER JOIN old_csv AS o ON #{join_statement};"
      [0, 1].each do |t|
        db.transaction do |trans|
          res.each do |r|
            trans.execute "DELETE FROM " + (t == 0 ? 'new_csv' : 'old_csv') + " WHERE id=#{r[t]}"
          end
        end
      end

      db.execute "UPDATE old_csv SET status='deleted'"
      res = db.execute 'SELECT * FROM old_csv'
      res.each { |r| diff << r[1, r.length] }

      res = db.execute 'SELECT * FROM new_csv'
      res.each { |r| diff << r[1, r.length] }
    ensure
      db.close if @db
    end

    p "CSV diff completed."

    # Return an array representation of the differentiated CSV
    diff
  end

  def self.write(csv_array, output)
    # Writes a csv_array to output
    CSV.open(output, "w") { |csv_out|
      csv_array.each do |row|
        csv_out << row
      end
    }
  end

  def self.extract(zip_path)
    require "zip"
    # Using provided path, extract files from zip archive into memory
    Zip::File.open(File.expand_path(zip_path)) do |zip_file|
      csvs = []
      zip_file.each { |entry|
        puts "Extracting #{entry.name}"
        # Read file contents and parse as CSV
        csvs << CSV.parse(entry.get_input_stream.read)
      }
      # Return array of separate CSVs
      csvs
    end
  end

  def self.archive(csv_arrays, zip_name = "SIS_Import.zip")
    # Given an array of CSV arrays (4 dimensional), construct a zip file containing CSV files
  end

  def self.upload()
    # Upload to canvas
  end

  def self.download()
    # Download current CSV report from Canvas
  end

  def self.run(old_path, new_path, output_path)
    self.write(self.diff(old_path, new_path), output_path)
  end
end

def cli_run
  require "optparse"

  options = {}
  OptionParser.new do |opts|
    opts.banner = "Usage: ruby csv-diff.rb [options] old-csv new-csv"

    opts.on("-v", "--[no-]verbose", "Output additional information to stdout.") do |v|
      options[:verbose] = v
    end

    opts.on("-o", "--output [FILE]", "Specify a location to write to a file.") do |o|
      throw "Output location not specified." unless o
      #TODO - handle invalid dirs
      # throw "Output location not valid." unless o.
      options[:output] = File.expand_path o
    end

  end.parse!

  p options

  old_path, new_path = ARGV

  # TODO: throw errors if old-csv or new-csv don't exist
  throw "Output file not provided! Use the \"-o [File Name]\" switch to specify a file path and name ( -o ./new.csv )." unless options[:output]

  CSVDiff::run(old_path, new_path, options[:output])
end

cli_run if __FILE__ == $0
