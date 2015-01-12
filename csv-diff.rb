#!/usr/env/ruby

# Takes an old CSV and a new CSV and outputs any new data in the new CSV in the form of a CSV.
# csv-diff <old-csv> <new-csv> -o <output-file> => <changes>

module CSVDiff
  require "csv"
  require "rest_client"
  require "json"
  require "fileutils"
  require "net/http"

  def self.verbose; @verbose; end
  def self.verbose=(bool); @verbose = bool; end

  def self.diff(old_csv, new_csv)
    require "sqlite3"

    # Get CSV headers
    old_header, new_header = [old_csv, new_csv].map(&:first)
    header = old_header # pointless, but clearer

    # Check for errors
    throw "Headers do not match." unless old_header == new_header

    # Create new CSV array (to be later written to file)
    diff = [header]

    puts "Calculating changes between CSV files..." if self.verbose
    begin
      db = SQLite3::Database.new ":memory:"

      create_query = proc { |table|
        sql_table_headers = header.collect { |h| h + " TEXT" }.join(", ")
        "CREATE TABLE " << table << "(" << sql_table_headers << ")"
      }

      insert_query = proc { |table, row|
        sql_header = header.join(", ").chomp(", ")
        sql_binds = ("?, " * row.length).chomp(", ")
        "INSERT INTO " << table << " (" << sql_header << ") VALUES (" << sql_binds << ")"
      }

      ["new_csv", "old_csv", "old_diff"].each { |t|
        db.execute create_query.call(t)
      }

      db.transaction do |trans|
        new_csv[1..-1].each do |r|
          trans.query(insert_query.call("new_csv", r), r)
        end

        old_csv[1..-1].each do |r|
          trans.query(insert_query.call("old_csv", r), r)
        end
      end

      new_diff = db.execute "SELECT * FROM new_csv EXCEPT SELECT * FROM old_csv INTERSECT SELECT * FROM new_csv"
      db.execute "INSERT INTO old_diff SELECT * FROM old_csv EXCEPT SELECT * FROM new_csv INTERSECT SELECT * FROM old_csv"
      db.execute "UPDATE old_diff SET status='deleted'"
      old_diff = db.execute "SELECT * FROM old_diff"

      diff.concat new_diff
      diff.concat old_diff
    ensure
      db.close if @db
    end

    puts "CSV diff completed." if self.verbose

    # Return an array representation of the differentiated CSV
    diff
  end

  # Loads a CSV file and returns an array of arrays
  def self.load(path)
    puts "Loading " << File.basename(path) if self.verbose
    begin
      file = File.new File.expand_path(path)
    rescue Exception => e
      raise ArgumentError, "There was a problem loading the file " << path << ".\n" << e.message
    end
    f = file.read
    f2 = f.gsub(/\r\n?/, "\n")
    puts "zut" if f2[/\r\n?/]
    CSV.parse f2
  end

  def self.write(csv_array, output = nil)
    # Writes a csv_array to output
    writer = proc { |csv_out|
      csv_array.each do |row|
        csv_out << row
      end
    }

    if output
      CSV.open(output, "w") { |out| writer.call(out) }
    else
      CSV(&writer)
    end
  end

  def self.extract(zip_path)
    require "zip"
    # Using provided path, extract files from zip archive into memory
    Zip::File.open(File.expand_path(zip_path)) do |zip_file|
      csvs = {}
      zip_file.each { |entry|
        name = File.basename entry.name
        next unless File.extname(name) == '.csv' && !entry.name[/_MACOSX/]
        puts "Extracting #{name}" if self.verbose
        # Read file contents and parse as CSV
        csvs[name] = CSV.parse(entry.get_input_stream.read.gsub(/\r\n?/, "\n"))
      }
      # Return hash of separate CSVs
      csvs
    end
  end

  def self.archive(csvs, zip_name = "SIS_Import.zip")
    require "zip"
    # Given a hash of 3D CSV arrays (with filenames as keys), construct a zip file containing CSV files
    path = File.expand_path(zip_name)
    Zip::OutputStream.open(path) { |os|
      csvs.keys.each { |filename|
        os.put_next_entry filename
        csvs[filename].each { |row|
          os.puts row.to_csv
        }
      }
    }
    path
  end

  def self.upload(file, uri, token)
    # Upload to canvas
    uri = URI(uri)
    Net::HTTP.start(uri.host, uri.port, :use_ssl => uri.scheme == 'https',
                    :verify_mode => OpenSSL::SSL::VERIFY_NONE) do |http|

      request = Net::HTTP::Post.new uri.request_uri

      request.initialize_http_header({
        'Authorization' => 'Bearer ' + token
      })

      #request.set_form_data {
      #  'import_type' => 

      response = http.request request
      CanvasToolkit::handle_canvas_errors response

      body = response.body
      return body, response.code.to_i
    end
  end

  def self.download(loc, uri, token)
    # Download current CSV report from Canvas
  end

  def self.run(old_path, new_path, output_path)
    self.write(
      self.diff(self.load(old_path), self.load(new_path)),
      output_path)
  end

  def self.run_zip(old_path, new_path, output_path)
    old_csvs = self.extract old_path
    new_csvs = self.extract new_path

    diffed_csvs = {}
    new_csvs.keys.each { |filename|
      new_csv = new_csvs[filename]
      old_csv = old_csvs.values.find { |old| old[0] == new_csv[0] }
      throw "The headers in one or more of the included files do not match." unless old_csv
      puts "Performing diff for " << filename if self.verbose
      diffed_csvs[filename] = self.diff old_csv, new_csv
    }

    puts "Archiving diff'ed CSVs to " << (output_path || "SIS_Import.zip") if self.verbose
    self.archive(diffed_csvs, output_path)
  end

end

def cli_run
  require "optparse"

  options = {
    run: true,
    zip: false
  }
  OptionParser.new do |opts|
    opts.banner = "Usage: ruby csv-diff.rb [options] old-csv new-csv"

    opts.on("-v", "--[no-]verbose", "Output additional information to stdout.") do |v|
      CSVDiff::verbose = true
    end

    opts.on("-o", "--output FILE", "Specify a location to write to a file.") do |o|
      throw "Output location not specified." unless o
      #TODO - handle invalid dirs
      # throw "Output location not valid." unless o.
      options[:output] = File.expand_path o
    end

    opts.on("-a", "--archive list,of,csvs", Array, "List of CSVs to add to ZIP archive. Files provided should be in same directory as script.") do |list|
      options[:run] = false
      csvs = {}
      list.each { |filename|
        csvs[filename] = CSVDiff::load(filename)
      }
      CSVDiff::archive csvs, options[:output] || "SIS Imports.zip"
    end

    opts.on("-z", "--zip", "Compare CSVs in two zip archives. Note: The headers for a CSV in one archive must match at least one CSV's header in the other archive.") do
      options[:zip] = true
    end

    opts.on("-u", "--upload URL", "Upload an SIS ZIP archive to your Canvas instance.") do |url|

    end

    opts.on("-d", "--download URL", "Download an SIS ZIP archive from your Canvas instance.") do |url|

    end

  end.parse!

  if options[:run]
    old_path, new_path = ARGV
    old_ext, new_ext = [old_path, new_path].map { |p| File.extname p.downcase }

    # TODO: Default to stdout so this can be removed
    throw "Only CSV and ZIP files are accepted. Both files must be the same type." unless old_ext == new_ext && (old_ext == '.zip' || old_ext == '.csv')
    throw "Output file not provided! Use the \"-o [File Name]\" switch to specify a file path and name ( -o ./new.zip )." unless options[:output] && old_ext == '.zip'

    if old_ext == '.zip'
      CSVDiff::run_zip(old_path, new_path, options[:output])
    else
      CSVDiff::run(old_path, new_path, options[:output])
    end
  end
end

cli_run if __FILE__ == $0
