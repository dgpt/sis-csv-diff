require './csv-diff'
Shoes.app(title: "Canvas CSV Comparator",
          width: 450, height: 250, resizable: false) do

  background white
  @margins = {
    stack: 6,
    button: 4
  }

  stack(margin: @margins[:stack], width: '100%') do

    flow(width: '100%') do
      title "SIS CSV Comparator", font_size: 18
    end

    # file select buttons for old/new CSVs
    # -- should accept CSV or ZIP files only
    # -- Should explain the difference between "old" and "new" data
    # --- use a little ? icon with tooltip

    flow(width: '100%') do
      stack(width: '50%') do
        @old_para = inscription "Please select a CSV containing your institution's current SIS data."
      end

      stack(width: '50%') do
        button("Select Current CSV", margin: @margins[:button], top: @old_para.top) do
          @old_path = ask_open_file
          @old_para.replace @old_path
        end
      end
    end

    flow(width: '100%') do
      stack(width: '50%') do
        @new_para = inscription "Please select a CSV containing the new data you wish to upload to Canvas."
      end

      stack(width: '50%') do
        button("Select New CSV", margin: @margins[:button]) do
          @new_path = ask_open_file
          @new_para.replace @new_path
        end
      end
    end

    # - Go button
    # -- Prompts for new file's location, initiates diff
    # -- Grayed out until old and new csvs are selected
    # -- Determine output file type based on input file types
    # -- If input file types do not match, raise an error
    flow(width: '100%') do
      button("Go", margin: @margins[:button], left: 0.5) do
        @output_path = ask_save_file

        # If script throws an error, create a popup to display message to user
        begin
          CSVDiff::run(@old_path, @new_path, @output_path)
        rescue Exception => e
          alert "An error occurred: " << e.message
        end
      end
    end
  end
end

# Requirements


# - (TODO when script finished) Canvas URL input box
# - Canvas Auth token input box -- needs *s to obscure token
# -- Look into making this save data so they don't have to re-type the URL
